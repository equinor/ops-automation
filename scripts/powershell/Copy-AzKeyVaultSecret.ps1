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
  .\Copy-AzKeyVaultSecret.ps1 -VaultName example-vault -TargetVaultName example-vault-02

  .EXAMPLE
  .\Copy-AzKeyVaultSecret.ps1 -VaultName example-vault -TargetVaultName example-vault-02 -Name storage--primary-connection-string, storage--secondary-connection-string

  .EXAMPLE
  .\Copy-AzKeyVaultSecret.ps1 -VaultName example-vault -TargetVaultName example-vault-02 -Force

  .EXAMPLE
  .\Copy-AzKeyVaultSecret.ps1 -VaultName example-vault -TargetVaultName example-vault-02 -SubscriptionId a8aa6166-3ab2-463c-b9d2-b3b277a2b70a -TargetSubscriptionId f8785e9b-2e41-4ffa-b693-33808fb24d3e
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

$ParameterSetName = $PSCmdlet.ParameterSetName
Write-Information "Parameter set name: $ParameterSetName"

Write-Information "Vault name: $VaultName"
Write-Information "Target vault name: $TargetVaultName"

$CopyCrossSubscription = $ParameterSetName -eq "CrossSubscription"
if ($CopyCrossSubscription) {
  Write-Information "Subscription ID: $SubscriptionId"
  $Context = Set-AzContext -SubscriptionId $SubscriptionId
  $SubscriptionName = $Context.Subscription.Name
  Write-Information "Subscription name: $SubscriptionName"
}

$IpAddress = Invoke-RestMethod "https://api.ipify.org"
Write-Information "IP address: $IpAddress"

$IpAddressRange = "$IpAddress/32"
$Vault = Get-AzKeyVault -VaultName $VaultName
$AddNetworkRule = $Vault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange
$Secrets = @()
try {
  if ($AddNetworkRule) {
    Write-Information "Adding IP address range '$IpAddressRange' to Key Vault '$VaultName'"
    $null = $Vault | Add-AzKeyVaultNetworkRule -IpAddressRange $IpAddressRange
  }

  Write-Information "Getting secrets from Key Vault '$VaultName'"
  # Using Get-AzKeyVaultSecret to get all secrets does not return secret values.
  # Use Get-AzKeyVaultSecret to get all secret names, then use Get-AzKeyVaultSecret to get secret value for each secret name.
  ($Vault | Get-AzKeyVaultSecret).Name | ForEach-Object { $Secrets += $Vault | Get-AzKeyVaultSecret -Name $_ }
}
catch {
  Write-Host "An error occurred:"
  Write-Host $_
}
finally {
  if ($AddNetworkRule) {
    Write-Information "Removing IP address range '$IpAddressRange' from Key Vault '$VaultName'"
    $null = $Vault | Remove-AzKeyVaultNetworkRule -IpAddressRange $IpAddressRange
  }
}

if ($Name.Count -gt 0) {
  Write-Information "Filtering all secrets from Key Vault '$VaultName' to secrets of the specified names"
  $Secrets = $Secrets | Where-Object { $_.Name -in $Name }
}

if ($CopyCrossSubscription) {
  Write-Information "Target subscription ID: $TargetSubscriptionId"
  $Context = Set-AzContext -SubscriptionId $TargetSubscriptionId
  $TargetSubscriptionName = $Context.Subscription.Name
  Write-Information "Target subscription name: $TargetSubscriptionName"
}

$TargetVault = Get-AzKeyVault -VaultName $TargetVaultName
$AddNetworkRule = $TargetVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange
try {
  if ($AddNetworkRule) {
    Write-Information "Adding IP address range '$IpAddressRange' to target Key Vault '$TargetVaultName'"
    $null = $TargetVault | Add-AzKeyVaultNetworkRule -IpAddressRange $IpAddressRange
  }

  foreach ($Secret in $Secrets) {
    $TargetName = $Secret.Name
    $TargetSecret = $TargetVault | Get-AzKeyVaultSecret -Name $TargetName

    if ($null -eq $TargetSecret -or $Force) {
      $TargetExpires = $Secret.Expires
      $TargetSecretValue = $Secret.SecretValue

      Write-Information "Setting secret '$TargetName' in target Key Vault '$TargetVaultName'"
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
    $null = $TargetVault | Remove-AzKeyVaultNetworkRule -IpAddressRange $IpAddressRange
  }
}
