<#
  .SYNOPSIS
  Copies key vault secrets to a target key vault.

  Prerequisites for identity or service principal that will run this script:
    - RBAC as Key Vault Contributor for Source and Destination Vault
    - Read access policy for secrets at source Key Vault and Write access policy for secrets at destination Key Vault

  .PARAMETER VaultName
  Specifies the name of the source key vault.

  .PARAMETER TargetVaultName
  Specifies the name of the target key vault.

  .PARAMETER SubscriptionId
  Specifies the ID of source Azure Subscription.

  .PARAMETER TargetSubscriptionId
  Specifies the ID of target Azure Subscription.

  .PARAMETER SecretName
  Specifies the name of the secret to copy. You can as well specify multiple SecretNames for multiple secrets to copy.
  Filters all secrets to the secrets of the specified names.

  .PARAMETER Force
  Forces the script to copy regardless if secret exist in target Key vault.

  .EXAMPLE
  This example shows how to copy all secrets from source to target vault within the same subscription.
  If secret exists in target Key vault, it will not be copied.
  .\Copy-AzKeyVaultSecret.ps1 -SubscriptionId <String> -VaultName <String> -TargetVaultName <String>

  .EXAMPLE
  Similar to example above, this shows how to copy all secrets from source to target vault within the same subscription.
  Secret will be copied even if it already exist in target Key vault.
  .\Copy-AzKeyVaultSecret.ps1 -SubscriptionId <String> -VaultName <String> -TargetVaultName <String> -Force

  .EXAMPLE
  This example shows how to copy all secrets when vaults reside in different Azure Subscriptions:
  .\Copy-AzKeyVaultSecret.ps1 -SubscriptionId <String> -TargetSubscriptionId <String> -VaultName <String> -TargetVaultName <String>
#>

param (
  [Parameter(Mandatory = $true)]
  [string]$VaultName,

  [Parameter(Mandatory = $true)]
  [string]$TargetVaultName,

  [Parameter(Mandatory = $false)]
  [string[]]$SecretName,

  [Parameter(Mandatory = $false)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TargetSubscriptionId = $SubscriptionId,

  [Parameter(Mandatory = $false)]
  [switch]$Force
)

if ($SubscriptionId -ne "") {
  Write-Information "Setting Azure context"
  $Context = Set-AzContext -SubscriptionId $SubscriptionId
}
else {
  Write-Information "Getting Azure context"
  $Context = Get-AzContext
}
$SubscriptionName = $Context.Subscription.Name
Write-Information "Subscription: $SubscriptionName ($SubscriptionId)"

$IpAddress = Invoke-RestMethod "https://api.ipify.org"
$IpAddressRange = "$IpAddress/32"
Write-Information "IP address: $IpAddress"

$Vault = Get-AzKeyVault -VaultName $VaultName
$AddNetworkRule = $Vault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

$Secrets = @()

try {
  if ($AddNetworkRule) {
    Write-Information "Adding IP address range '$IpAddressRange' to Key Vault '$VaultName'"
    $null = Add-AzKeyVaultNetworkRule -VaultName $VaultName -IpAddressRange $IpAddressRange
  }

  Write-Information "Getting secrets from Key Vault '$VaultName'"
  (Get-AzKeyVaultSecret -VaultName $VaultName).Name | ForEach-Object {
    $Secrets += (Get-AzKeyVaultSecret -VaultName $VaultName -Name $_)
  }
}
catch {
  Write-Host "An error occurred:"
  Write-Host $_
}
finally {
  if ($AddNetworkRule) {
    Write-Information "Removing IP address range '$IpAddressRange' from Key Vault '$VaultName'"
    $null = Remove-AzKeyVaultNetworkRule -VaultName $VaultName -IpAddressRange $IpAddressRange
  }
}

if ($SecretName.Count -gt 0) {
  Write-Information "Filtering all secrets from Key Vault '$VaultName' to the secrets of the specified names"
  $Secrets = $Secrets | Where-Object { $_.Name -in $SecretName }
}

if ($TargetSubscriptionId -ne $SubscriptionId) {
  Write-Information "Setting Azure context"
  $Context = Set-AzContext -SubscriptionId $TargetSubscriptionId
  $SubscriptionName = $Context.Subscription.Name
  Write-Information "Target subscription: $SubscriptionName ($SubscriptionId)"
}

$TargetVault = Get-AzKeyVault -VaultName $TargetVaultName
$AddNetworkRule = $TargetVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  if ($AddNetworkRule) {
    Write-Information "Adding IP address range '$IpAddressRange' to target Key Vault '$TargetVaultName'"
    $null = Add-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }

  foreach ($Secret in $Secrets) {
    $TargetSecretName = $Secret.Name
    $TargetSecret = Get-AzKeyVaultSecret -VaultName $TargetVaultName -Name $TargetSecretName

    if ($null -eq $TargetSecret -or $Force) {
      Write-Information "Setting secret '$TargetSecretName' in target Key Vault '$TargetVaultName'"
      $TargetSecret = Set-AzKeyVaultSecret -VaultName $TargetVaultName -Name $TargetSecretName -Expires $Secret.Expires -SecretValue $Secret.SecretValue
    }
    else {
      Write-Information "Secret '$TargetSecretName' already exists in target Key Vault '$TargetVaultName'"
    }
  }
}
catch {
  Write-Host "An error occurred:"
  Write-Host $_
}
finally {
  if ($AddNetworkRule) {
    Write-Information "Removing IP address range '$IpAddressRange' from target Key Vault '$TargetVaultName'"
    $null = Remove-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }
}
