<#
  .SYNOPSIS
  Copies key vault secrets to a target key vault.

  Prerequisites for identity or service principal that will run this script:
    - RBAC as Key Vault Contributor for Source and Destination Vault
    - Read access policy for secrets at source Key Vault and Write access policy for secrets at destination Key Vault

  .PARAMETER SourceVaultName
  Specifies the name of the source key vault.

  .PARAMETER TargetVaultName
  Specifies the name of the target key vault.

  .PARAMETER SubscriptionId
  Specifies the ID of source Azure Subscription.

  .PARAMETER TargetSubscriptionId
  Specifies the ID of target Azure Subscription.

  .PARAMETER Force
  Forces the script to copy regardless if secret exist in target Key vault.

  .EXAMPLE
  This example shows how to copy all secrets from source to target vault within the same subscription.
  If secret exists in target Key vault, it will not be copied.
  .\Copy-AzKeyVaultSecret.ps1 -SubscriptionId <String> -SourceVaultName <String> -TargetVaultName <String>

  .EXAMPLE
  Similar to example above, this shows how to copy all secrets from source to target vault within the same subscription.
  Secret will be copied even if it already exist in target Key vault.
  .\Copy-AzKeyVaultSecret.ps1 -SubscriptionId <String> -SourceVaultName <String> -TargetVaultName <String> -Force

  .EXAMPLE
  This example shows how to copy all secrets when vaults reside in different Azure Subscriptions:
  .\Copy-AzKeyVaultSecret.ps1 -SubscriptionId <String> -TargetSubscriptionId <String> -SourceVaultName <String> -TargetVaultName <String>
#>

param (
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TargetSubscriptionId = $SubscriptionId,

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

$Context = Set-AzContext -Subscription $SubscriptionId
Write-Information "Current subscription: $($Context.Subscription.Name)"

$SourceVault = Get-AzKeyVault -VaultName $SourceVaultName
$AddNetworkRule = $SourceVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  if ($AddNetworkRule) {
    Write-Information "Add IP address to source Key vault"
    $null = Add-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }

  Write-Information "Get list of secrets names"
  $SourceVaultSecretNames = (Get-AzKeyVaultSecret -VaultName $SourceVaultName).Name

  $SourceVaultSecrets = @()
  $SourceVaultSecretNames | ForEach-Object {
    $SourceVaultSecrets += (Get-AzKeyVaultSecret -VaultName $SourceVaultName -Name $_)
  }
}
catch {
  Write-Error "An error occurred: $($_.ErrorDetails)"
}
finally {
  if ($AddNetworkRule) {
    Write-Information "Remove IP address from source Key vault"
    $null = Remove-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }
}

Write-Information "If target subscription is specified, switch to target context"
if ($TargetSubscriptionId -ne $SubscriptionId) {
  $Context = Set-AzContext -Subscription $TargetSubscriptionId
  Write-Information "Target subscription: $($Context.Subscription.Name)"
}

$TargetVault    = Get-AzKeyVault -VaultName $TargetVaultName
$AddNetworkRule = $TargetVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  if ($AddNetworkRule) {
    Write-Information "Add IP address to target Key vault"
    $null = Add-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }

  # Copy secrets to target vault
  $SourceVaultSecrets | ForEach-Object {
    $TargetVaultSecretName = $_.Name
    $TargetVaultSecret     = Get-AzKeyVaultSecret -VaultName $TargetVaultName -Name $TargetVaultSecretName

    # Skip if secret exist in target vault
    if ($TargetVaultSecret -eq $null -or $Force) {
      $TargetVaultSecretExpDate = $_.Expires
      $SecretValue              = $_.SecretValue

      # Add if secret does not exist, orparameter -Force is used
      $Copy = Set-AzKeyVaultSecret -VaultName $TargetVaultName -Name $_.Name -Expires $TargetVaultSecretExpDate -SecretValue $SecretValue
      Write-Information "Successfully replicated secret '$($Copy.Id)' "
    }
    else {
      # Secret already exists
      Write-Information "Secret '$($_.Id)' already copied"
    }
  }
}
catch {
    Write-Error "An error occurred: $($_.ErrorDetails)"
}
finally {
  if ($AddNetworkRule) {
    Write-Information "Remove IP address from target Key vault"
    $null = Remove-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }
}
