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

  .PARAMETER SecretName
  Specifies the name of the secret to copy. You can as well specify multiple SecretNames for multiple secrets to copy.

  .PARAMETER SkipSecrets
  Specifies the names of the secrets to skip during copy operation.

  .PARAMETER Force
  Forces the script to run without asking for user confirmation.

  .PARAMETER Runbook
  Trigger script function to login using runbook managed identity.

  .EXAMPLE
  This example shows how to copy all secrets from source to target vault.
  It requires manual user confirmation before executing copy operation for every secret separately:
  .\Copy-AzKeyVaultSecret.ps1 -SourceVaultName <String> -TargetVaultName <String> -SubscriptionId <String>

  .EXAMPLE
  Similar to example above, this shows how to copy all secrets from source to target vault.
  But this time the script does not require user confirmation as it uses -Force argument.
  .\Copy-AzKeyVaultSecret.ps1 -SourceVaultName <String> -TargetVaultName <String> -SubscriptionId <String> -Force

  .EXAMPLE
  This example shows how to use $SecretName Parameter to copy a single secret:
  .\Copy-AzKeyVaultSecret.ps1 -SourceVaultName <String> -TargetVaultName <String> -SubscriptionId <String> -SecretName <String>

  .EXAMPLE
  This example shows how to use $SecretName Parameter to copy multiple secrets:
  .\Copy-AzKeyVaultSecret.ps1 -SourceVaultName <String> -TargetVaultName <String> -SubscriptionId <String> -SecretName <String>, <String>, <String>

  .EXAMPLE
  This example shows how to copy all secrets without confirmation when vaults reside in different Azure Subscriptions:
  .\Copy-AzKeyVaultSecret.ps1 -SourceVaultName <String> -TargetVaultName <String> -SubscriptionId <String> -TargetSubscriptionId <String> -Force

  .EXAMPLE
  This example shows the same example as previous + use of SkipSecrets Parameter. SkipSecrets supports multiple values:
  .\Copy-AzKeyVaultSecret.ps1 -SourceVaultName <String> -TargetVaultName <String> -SubscriptionId <String> -TargetSubscriptionId <String> -Force -SkipSecrets <String>, <String>, <String>
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$SourceVaultName,

    [Parameter(Mandatory = $true)]
    [string]$TargetVaultName,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$TargetSubscriptionId,

    [Parameter(Mandatory = $false)]
    [string[]]$SecretName,

    [Parameter(Mandatory = $false)]
    [string[]]$SkipSecrets,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$Runbook
)

$InformationPreference = 'Continue'

# Log into Azure using a managed identity, for use in an Azure Automation Runbook.
function aaLogin {
    Disable-AzContextAutosave -Scope Process
    $AzureContext = (Connect-AzAccount -Identity).context
    Set-AzContext -SubscriptionId $SubscriptionId -DefaultProfile $AzureContext
}

# Set and verify Azure Subscription Context
function Set-Subscription {

    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    # Set Context to correct Subscription.
    Set-AzContext -SubscriptionId $SubscriptionId

    # Verify Subscription Context
    $subCheck = (Get-AzContext).Subscription.Id
    try {
        if ($subCheck -ne $SubscriptionId) {
            Write-Error "Error: Subscription Mismatch, check context!"
            exit 1
        }
    }
    catch {
        Write-Error "Error: $($_.Exception.Message)"
    }
}

# Temporarily disable Key Vault firewall to allow script to read secrets in Source Vault and write secrets in Target Vault.
function Disable-KeyVaultFirewall {

    param (
        [Parameter(Mandatory = $true)]
        [string]$VaultName
    )

    $Vault = Get-AzKeyVault -VaultName $VaultName -ErrorAction SilentlyContinue
    $FirewallDefaultAction = $Vault.NetworkAcls.DefaultAction
    $FirewallEnabled = $FirewallDefaultAction -eq 'Deny'

    if ($FirewallEnabled) {
        $null = Update-AzKeyVaultNetworkRuleSet -VaultName $VaultName -DefaultAction 'Allow'
    }

    return $FirewallEnabled
}

# Convert SecureString to PlainText (Temporarily for comparison purposes)
function Convert-SecureStringToPlainText {
    param (
        [Parameter(Mandatory = $true)]
        [SecureString]$SecureString
    )
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString))
}

try {
    if ($Runbook) {
        aaLogin
    }

    # Set Context and make sure FireWall is set to "Allowed" to be able to access secrets
    Set-Subscription -SubscriptionId $SubscriptionId
    $SourceVaultFirewall = Disable-KeyVaultFirewall -VaultName $SourceVaultName
    $TargetVaultFirewall = Disable-KeyVaultFirewall -VaultName $TargetVaultName

    # Check if Source and Target Vaults exist
    $SourceVault = Get-AzKeyVault -VaultName $SourceVaultName -ErrorAction SilentlyContinue
    $TargetVault = Get-AzKeyVault -VaultName $TargetVaultName -ErrorAction SilentlyContinue

    if ($SourceVault -and $TargetVault) {
        # Skip Secrets from Copy operation if specified in $SkipSecrets Parameter
        $exclusionList = @()
        if ($SkipSecrets) {
            $exclusionList += $SkipSecrets
        }

        # Run this block if no input in parameter $SecretName specified
        if (!$SecretName) {
            if ($SkipSecrets) {
                $SecretName = (Get-AzKeyVaultSecret -VaultName $SourceVaultName).Name | Where-Object { -not $exclusionList.Contains($_) } | Sort-Object
            }

            else {
                $SecretName = (Get-AzKeyVaultSecret -VaultName $SourceVaultName).Name | Sort-Object
            }
        }

        foreach ($n in $SecretName) {
            # Get secret from source Key Vault
            $SourceSecret = Get-AzKeyVaultSecret -VaultName $SourceVaultName -Name $n -ErrorAction SilentlyContinue
            $SourceSecretValue = Convert-SecureStringToPlainText -secureString $SourceSecret.SecretValue

            # Set Target Subscription Context if available
            if ($TargetSubscriptionId) {
                $null = Set-AzContext -SubscriptionId $TargetSubscriptionId
            }

            # Get target secret from target Key Vault
            $TargetSecret = Get-AzKeyVaultSecret -VaultName $TargetVaultName -Name $n -ErrorAction SilentlyContinue
            $TargetSecretValue = Convert-SecureStringToPlainText -secureString $TargetSecret.SecretValue

            # Compare Source and Target Secret Values
            if ($SourceSecretValue -ne $TargetSecretValue) {
                $Copy = Set-AzKeyVaultSecret `
                    -VaultName $TargetVaultName `
                    -SecretValue $SourceSecret.SecretValue `
                    -Name $SourceSecret.Name `
                    -Expires $SourceSecret.Expires `
                    -ContentType $SourceSecret.ContentType `
                    -Tag $SourceSecret.Tags `
                    -Confirm:(!$Force)
                Write-Output "Successfully copied secret name '$($Copy.Name)' with id '$($Copy.Id)'"
            }

            else {
                Write-Output "Secret Name '$($SourceSecret.Name)' with id '$($SourceSecret.Id)' already exists in destination vault"
            }
        }
    }
}

catch {
    Write-Error "Error: $($_.Exception.Message)"
}

finally {
    # Void secrets
    $SourceSecretValue = ""
    $TargetSecretValue = ""

    # Switch Source Vault Firewall back to Deny if default action was 'Deny'
    if ($SourceVaultFirewall) {
        $null = Update-AzKeyVaultNetworkRuleSet -VaultName $SourceVaultName -DefaultAction 'Deny'

        Write-Output "Firewall for Source Vault is set to $SourceVaultFirewall."
    }

    # Switch Target Vault Firewall back to Deny if default action was 'Deny'
    if ($TargetVaultFirewall) {
        $null = Update-AzKeyVaultNetworkRuleSet -VaultName $TargetVaultName -DefaultAction 'Deny'

        Write-Output "Firewall for Target Vault is set to $SourceVaultFirewall."
    }
}
