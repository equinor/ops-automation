<#
  .SYNOPSIS
  Copies key vault secrets to a target key vault.

  Prerequisites for identity or service principal that will run this script:
    - RBAC as Key Vault Contributor for Source and Destination Vault
    - Read access policy for secrets at source Key Vault and Write access policy for secrets at destination Key Vault

  .PARAMETER SourceSubscriptionId
  Specifies the ID of source Azure Subscription. Mandatory.

  .PARAMETER TargetSubscriptionId
  Specifies the ID of target Azure Subscription. Can be omitted.

  .PARAMETER SourceVaultName
  Specifies the name of the source key vault. Mandatory.

  .PARAMETER TargetVaultName
  Specifies the name of the target key vault. Mandatory.

  .PARAMETER Force
  Forces the script to copy regardless if secret exist in target Key vault. Can be omitted.

  .EXAMPLE
  This example shows how to copy all secrets from source to target vault within the same subscription.
  If secret exists in target Key vault, it will not be copied.
  .\Copy-AzKeyVaultSecret.ps1 -SourceSubscriptionId <String> -SourceVaultName <String> -TargetVaultName <String>

  .EXAMPLE
  Similar to example above, this shows how to copy all secrets from source to target vault within the same subscription.
  Secret will be copied even if it already exist in target Key vault.
  .\Copy-AzKeyVaultSecret.ps1 -SourceSubscriptionId <String> -SourceVaultName <String> -TargetVaultName <String> -Force

  .EXAMPLE
  This example shows how to copy all secrets when vaults reside in different Azure Subscriptions:
  .\Copy-AzKeyVaultSecret.ps1 -SourceSubscriptionId <String> -TargetSubscriptionId <String> -SourceVaultName <String> -TargetVaultName <String>
#>

param (
  [Parameter(Mandatory = $true)]
  [string]$SourceSubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TargetSubscriptionId = $SourceSubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$SourceVaultName,

  [Parameter(Mandatory = $true)]
  [string]$TargetVaultName,

  # Force overwrite existing secrets
  [Parameter(Mandatory = $false)]
  [switch]$Force
)

$IpAddress = (Invoke-RestMethod -Uri "https://api.ipify.org")
$IpAddressRange = "$IpAddress/32"
Write-Information "Current IP address: $IpAddress"

$Context = Set-AzContext -Subscription $SourceSubscriptionId
Write-Information "Current subscription: $($Context.Subscription.Name)"

$SourceVault = Get-AzKeyVault -VaultName $SourceVaultName
$AddNetworkRule = $SourceVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  # Add IP adderss to source Key vault
  if ($AddNetworkRule) {
    $null = Add-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }

  # Get list of secrets names
  $SourceVaultSecretNames = (Get-AzKeyVaultSecret -VaultName $SourceVaultName).Name

  $SourceVaultSecrets = @()
  $SourceVaultSecretNames | ForEach-Object {
    $SourceVaultSecrets += (Get-AzKeyVaultSecret -VaultName $SourceVaultName -Name $_)
  }
}
catch {
  Write-Error "An error occurred: $_"
}
finally {
  # Remove IP address from source Key vault
  if ($AddNetworkRule) {
    $null = Remove-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }
}

# Switch context to target subscription if $TargetSubscriptionId has value
if (![string]::IsNullOrEmpty($TargetSubscriptionId)) {
  $Context = Set-AzContext -Subscription $TargetSubscriptionId
  Write-Information "Target subscription: $($Context.Subscription.Name)"
}

$TargetVault = Get-AzKeyVault -VaultName $TargetVaultName
$AddNetworkRule = $TargetVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  # Add IP address to target Key vault
  if ($AddNetworkRule) {
    $null = Add-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }

  # Copy secrets
  $SourceVaultSecrets | ForEach-Object {
    $SourceVaultSecretName    = $($_.Name)    # Fetch secret name
    $SourceVaultSecretExpDate = $($_.Expires) # Fetch expiration date
    $TargetVaultSecret        = Get-AzKeyVaultSecret -VaultName $TargetVaultName -Name $SourceVaultSecretName
    $SecretValue              = $($_.SecretValue)

    # Skip if secret exists in target vault
    if ($TargetVaultSecret -eq $null -or $Force) {
      # Secret does not exist
      $Copy = Set-AzKeyVaultSecret -VaultName $TargetVaultName -Name $_.Name -Expires $SourceVaultSecretExpDate -SecretValue $SecretValue
      Write-Output "Successfully replicated secret '$($Copy.Id)'"
    }
    else {
      # Secret already exists
      Write-Output "Secret '$($_.Id)' already copied"
    }
  }
}
catch {
    Write-Error "An error occurred $_"
}
finally {
  # Remove IP address from target Key vault
  if ($AddNetworkRule) {
    $null = Remove-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }
}
