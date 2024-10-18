param (
  [Parameter(Mandatory = $true)]
  [string]$SourceSubscriptionId,

  # # Assume same subscription for now
  # [Parameter(Mandatory = $false)]
  # [string]$TargetSubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$SourceVaultName,

  [Parameter(Mandatory = $true)]
  [string]$TargetVaultName

  # # Use if we want to overwrite secrets that already exist
  # [Parameter(Mandatory = $false)]
  # [switch]$Force
)

# Write-Output "SourceSubscriptionId is: $SourceSubscriptionId"
# Write-Output "SourceVaultName is: $SourceVaultName"
# Write-Output "TargetVaultName is: $TargetVaultName"
# exit

# # TODO
# - Expiration date should be copied together with secret
# - Should allow copying across subscrptions
# - Should be able to force overwrite if secrets already exist

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

# # Assume same subscription for now
# #
# # Conditional: Should not execute if $TargetSubscriptionId == $null
# #
# # Set az context to target sub
# $Context = Set-AzContext -SubscriptionId $TargetSubscriptionId
# Write-Information "Current subscription: $($Context.Subscription.Name)"

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

  # Copy secrets
  $SourceVaultSecrets | ForEach-Object {
    # Get value of secret in plaintext to compare with target secret
    $Secret = Get-AzKeyVaultSecret -VaultName $_.VaultName -Name $_.Name -AsPlainText # -ErrorAction SilentlyContinue
    $Existing = Get-AzKeyVaultSecret -VaultName $TargetVaultName -Name $_.Name -AsPlainText # -ErrorAction SilentlyContinue
    if ($Secret -ne $Existing) {
        # Only copy if value of secret don't match target secret
        $SecretValue = $Secret | ConvertTo-SecureString -AsPlainText -Force
        $Backup = Set-AzKeyVaultSecret -VaultName $TargetVaultName -Name $_.Name -SecretValue $SecretValue
        Write-Output "Successfully backed up secret '$($Backup.Id)'"
    }
    else {
        Write-Output "Secret '$($_.Id)' already backed up"
    }
  }

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
