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

$IpAddress = Invoke-RestMethod "https://api.ipify.org"
$IpAddressRange = "$IpAddress/32"
Write-Information "Current IP address: $IpAddress"

$Context = Set-AzContext -SubscriptionId $SourceSubscriptionId
Write-Information "Current subscription: $($Context.Subscription.Name)"

$SourceVault = Get-AzKeyVault -VaultName $SourceVaultName
$AddNetworkRule = $SourceVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  # Legg til IP addresse på source key vault
  if ($AddNetworkRule) {
    $null = Add-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }
  # Hent secrets fra source key vault
  $SourceVaultSecrets = @()
  $SourceVaultSecrets += Get-AzKeyVaultSecret -VaultName $SourceVaultName
}
catch {
  # skriv feilmeldingen
}
finally {
  # Fjern IP addresse på source key vault
  if ($AddNetworkRule) {
    $null = Remove-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }
}

# Legg til: Hopp over hvis isje vi skal sammenligne med et annet subscription
# Set az context til target sub
$Context = Set-AzContext -SubscriptionId $TargetSubscriptionId
Write-Information "Current subscription: $($Context.Subscription.Name)"

$TargetVault = Get-AzKeyVault -VaultName $TargetVaultName
$AddNetworkRule = $TargetVault.NetworkAcls.IpAddressRanges -notcontains $IpAddressRange

try {
  # Legg til IP addresse på target key vault
  if ($AddNetworkRule) {
    $null = Add-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }
  # Legg secrets inn i target key vault
  $TargetVaultSecrets = @()
  $TargetVaultSecrets += Get-AzKeyVaultSecret -VaultName $TargetVaultName

  # Sammenlign secret navn og secret value --> Legg til hvis mangler + hopp over hvis finnes (unntatt hvis /1)
  $CompareSecretName = Compare-Object -ReferenceObject $SourceVaultSecrets -DifferenceObject $TargetVaultSecrets -Property Name
  # /1 - Hvis secret navn er likte men secret value er ulik --> overskriv secret value

  # if ($Force)
}
catch {
  # skriv feilmelding
}
finally {
  # Fjern IP addresse på target key vault
  if ($AddNetworkRule) {
    $null = Remove-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }
}

Write-Output $CompareSecretName
