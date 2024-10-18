param (
  [Parameter(Mandatory = $true)]
  [string]$SourceSubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TargetSubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$SourceVaultName,

  [Parameter(Mandatory = $true)]
  [string]$TargetVaultName,

  [Parameter(Mandatory = $false)]
  [switch]$Force
)

$IpAddress = (Invoke-RestMethod -Uri "https://api.ipify.org")
$IpAddressRange = "$IpAddress/32"
Write-Information "Current IP address: $IpAddress"

$Context = Set-AzContext -SubscriptionId $SourceSubscriptionId
Write-Information "Current subscription: $($Context.Subscription.Name)"

$SourceVault = Get-AzKeyVault -VaultName $SourceVaultName
$AddNetworkRule = $SourceVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  # Add IP adderss to source Key vault
  if ($AddNetworkRule) {
    $null = Add-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }
  # Get secrets from asource Key vault
  $SourceVaultSecrets = @()
  $SourceVaultSecrets += Get-AzKeyVaultSecret -VaultName $SourceVaultName
}
catch {
  # Generic error message. Look to improve
  Write-Error "An error occurred"
}
finally {
  # Remove IP address from source Key vault
  if ($AddNetworkRule) {
    $null = Remove-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }
}

# Conditional: Should not execute if $TargetSubscriptionId == $null
#
# Set az context to target sub
$Context = Set-AzContext -SubscriptionId $TargetSubscriptionId
Write-Information "Current subscription: $($Context.Subscription.Name)"

$TargetVault = Get-AzKeyVault -VaultName $TargetVaultName
$AddNetworkRule = $TargetVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  # Add IP address to target Key vault
  if ($AddNetworkRule) {
    $null = Add-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }
  # Add secrets to target Key vault
  $TargetVaultSecrets = @()
  $TargetVaultSecrets += Get-AzKeyVaultSecret -VaultName $TargetVaultName

  # Compare secret name and value with existing. Add only if not exist (except if /1)
  $CompareSecretName = Compare-Object -ReferenceObject $SourceVaultSecrets -DifferenceObject $TargetVaultSecrets -Property Name
  # /1 - If secret name is the same, but value differs: overwrite secret value

  # if ($Force)
}
catch {
    # Generic error message. Look to improve
    Write-Error "An error occurred"
}
finally {
  # Remove IP address from target Key vault
  if ($AddNetworkRule) {
    $null = Remove-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }
}

Write-Output $CompareSecretName
