param (
  [Parameter(Mandatory = $true)]
  [string]$SourceSubscriptionId,

  [Parameter(Mandatory = $false)]
  [string]$TargetSubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$SourceVaultName,

  [Parameter(Mandatory = $true)]
  [string]$TargetVaultName

  # # Use if we want to overwrite secrets that already exist
  # [Parameter(Mandatory = $false)]
  # [switch]$Force
)

##################################################################
###################### REMOVE AFTER TESTING ######################
##################################################################
Write-Output "SourceSubscriptionId is: $SourceSubscriptionId"
Write-Output "TargetSubscriptionId is: $TargetSubscriptionId"
Write-Output "SourceVaultName is: $SourceVaultName"
Write-Output "TargetVaultName is: $TargetVaultName"
Read-Host -Prompt "Press any key to continue or Ctrl-C to break..."

# # TODO
# √ - Expiration date should be copied together with secret
# √ - Should allow copying across subscrptions
#   - Should be able to force overwrite if secrets already exist

$IpAddress = (Invoke-RestMethod -Uri "https://api.ipify.org")
$IpAddressRange = "$IpAddress/32"
Write-Information "Current IP address: $IpAddress"

$Context = Set-AzContext -Subscription $SourceSubscriptionId
Write-Information "Current subscription: $($Context.Subscription.Name)"

# $SourceVault = Get-AzKeyVault -VaultName $SourceVaultName
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
    # $null = Remove-AzKeyVaultNetworkRule -VaultName $SourceVaultName -IpAddressRange $IpAddressRange
  }
}

# Switch context to target subscription if $TargetSubscriptionId has value
if (![string]::IsNullOrEmpty($TargetSubscriptionId)) {
  $Context = Set-AzContext -Subscription $TargetSubscriptionId
  Write-Information "Target subscription: $($Context.Subscription.Name)"
  Start-Sleep -Seconds 10
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
    $SourceVaultSecretName    = $($_.Name)
    $SourceVaultSecretExpDate = $($_.Expires)
    $TargetVaultSecretName    = (Get-AzKeyVaultSecret -VaultName $TargetVaultName -Name $SourceVaultSecretName).Name
    $SecretValue              = $($_.SecretValue)

    # Skip if secret exists in target vault
    if ($SourceVaultSecretName -ne $TargetVaultSecretName) {
      $Backup = (Set-AzKeyVaultSecret -VaultName $TargetVaultName -Name $_.Name -Expires $SourceVaultSecretExpDate -SecretValue $SecretValue)
      Write-Output "Successfully backed up secret '$($Backup.Id)'"
    }
    else {
      Write-Output "Secret '$($_.Id)' already backed up"
    }
  }
}
catch {
    Write-Error "An error occurred $_"
}
finally {
  # Remove IP address from target Key vault
  if ($AddNetworkRule) {
    # $null = Remove-AzKeyVaultNetworkRule -VaultName $TargetVaultName -IpAddressRange $IpAddressRange
  }
}
