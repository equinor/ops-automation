<#
  .SYNOPSIS
  Copies Key Vault secrets to a target Key Vault.

  .DESCRIPTION
  The Copy-AzKeyVaultSecret.ps1 script wraps the Get-AzKeyVaultSecret and Set-AzKeyVaultSecret cmdlets to simplify the process of copying Key Vault secrets to a target Key Vault.
  It will automatically check for and skip existing secrets in the target Key Vault.

  Prerequisites:
    - Azure roles "Key Vault Contributor" and "Key Vault Secrets User" at the Key Vault scope.
    - Azure roles "Key Vault Contributor" and "Key Vault Secrets Officer" at the target Key Vault scope.

  .PARAMETER VaultName
  The name of the Key Vault to copy secrets from.

  .PARAMETER TargetVaultName
  The name of the target Key Vault to copy secrets to.

  .PARAMETER SubscriptionId
  The ID of the subscription to copy Key Vault secrets from.

  .PARAMETER TargetSubscriptionId
  The ID of the subscription to copy Key Vault secrets to.

  .PARAMETER Name
  The name of the Key Vault secrets to copy.
  If not specified, all secrets will be copied.

  .PARAMETER Force
  Override existing secrets in target Key Vault.

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

[CmdletBinding(DefaultParameterSetName = "SingleSubscription")]
param (
  [Parameter(Mandatory = $true, ParameterSetName = "SingleSubscription")]
  [Parameter(Mandatory = $true, ParameterSetName = "CrossSubscription")]
  [string]$VaultName,

  [Parameter(Mandatory = $true, ParameterSetName = "SingleSubscription")]
  [Parameter(Mandatory = $true, ParameterSetName = "CrossSubscription")]
  [string]$TargetVaultName,

  [Parameter(Mandatory = $true, ParameterSetName = "CrossSubscription")]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true, ParameterSetName = "CrossSubscription")]
  [string]$TargetSubscriptionId,

  [Parameter(Mandatory = $false, ParameterSetName = "SingleSubscription")]
  [Parameter(Mandatory = $false, ParameterSetName = "CrossSubscription")]
  [string[]]$Name,

  [Parameter(Mandatory = $false, ParameterSetName = "SingleSubscription")]
  [Parameter(Mandatory = $false, ParameterSetName = "CrossSubscription")]
  [switch]$Force
)

$CrossSubscription = $PSCmdlet.ParameterSetName -eq "CrossSubscription"
if ($CrossSubscription) {
  Write-Information "Setting Azure context"
  $Context = Set-AzContext -SubscriptionId $SubscriptionId
  $SubscriptionName = $Context.Subscription.Name
  Write-Information "Subscription: $SubscriptionName ($SubscriptionId)"
}

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

if ($Name.Count -gt 0) {
  Write-Information "Filtering all secrets from Key Vault '$VaultName' to secrets of the specified names"
  $Secrets = $Secrets | Where-Object { $_.Name -in $Name }
}

if ($CrossSubscription) {
  Write-Information "Setting Azure context to target subscription"
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
    $TargetName = $Secret.Name
    $TargetSecret = Get-AzKeyVaultSecret -VaultName $TargetVaultName -Name $TargetName

    if ($null -eq $TargetSecret -or $Force) {
      Write-Information "Setting secret '$TargetName' in target Key Vault '$TargetVaultName'"
      $TargetExpires = $Secret.Expires
      $TargetSecretValue = $Secret.Value
      $TargetSecret = Set-AzKeyVaultSecret -VaultName $TargetVaultName -Name $TargetName -Expires $TargetExpires -SecretValue $TargetSecretValue
    }
    else {
      Write-Information "Secret '$TargetName' already exists in target Key Vault '$TargetVaultName'"
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
