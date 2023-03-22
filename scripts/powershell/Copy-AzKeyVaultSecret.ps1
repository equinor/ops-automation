<#
  .SYNOPSIS
  Copies key vault secrets to a target key vault.

  Prerequisites for identity or service principal that will run this script:
    - RBAC as Key Vault Contributor for Source and Destination Vault
    - Read access policy for secrets at source Key Vault and Write access policy for secrets at destination Key Vault

  .PARAMETER VaultName
  Specifies the name of the key vault.

  .PARAMETER TargetVaultName
  Specifies the name of the target key vault.

  .PARAMETER SubscriptionId
  Specifies the ID of Azure Subscription.

  .PARAMETER TargetSubscriptionId
  Specifies the ID of Target Azure Subscription.

  .PARAMETER Name
  Specifies the name of the secret to copy. You can as well specify multiple Names for multiple secrets to copy.

  .PARAMETER SkipSecrets
  Specifies the names of the secret skip copy operation.

  .PARAMETER Force
  Forces the script to run without asking for user confirmation.

  .PARAMETER Runbook
  Trigger script function to login using runbook managed identity.

  .EXAMPLE
  This example shows how to copy all secrets from source to target vault.
  It requires manual user confirmation before executing copy operation for every secret separately:
  .\Copy-AzKeyVaultSecret.ps1 -VaultName <String> -TargetVaultName <String> -Subscription $Subscription

  .EXAMPLE
  Similar to example above, this shows how to copy all secrets from source to target vault.
  But this time script does not require user confirmation as it uses -Force argument.
  .\Copy-AzKeyVaultSecret.ps1 -VaultName <String> -TargetVaultName <String> -Subscription $Subscription -Force

  .EXAMPLE
  This example shows how to use $Name Parameter to copy a single secret:
  .\Copy-AzKeyVaultSecret.ps1 -VaultName <String> -TargetVaultName <String> -Subscription $Subscription -Name <String>

  .EXAMPLE
  This example shows how to use $Name Parameter to copy multiple secrets:
  .\Copy-AzKeyVaultSecret.ps1 -VaultName <String> -TargetVaultName <String> -Subscription $Subscription -Name <String>, <String>, <String>

  .EXAMPLE
  This example shows how to copy all secrets from source to target vault without any confirmation:
  .\Copy-AzKeyVaultSecret.ps1 -VaultName <String> -TargetVaultName <String> -Subscription $Subscription -Force

  .EXAMPLE
  This example shows how to copy all secrets without confirmation when vaults resides in different Azure Subscriptions:
  .\Copy-AzKeyVaultSecret.ps1 -VaultName <String> -TargetVaultName <String> -SubscriptionId <String> -TargetSubscriptionId <String> -Force

  .EXAMPLE
  This example shows same example as previous + use of SkipSecrets Parameter. SkipSecrets support multiple values:
  .\Copy-AzKeyVaultSecret.ps1 -VaultName <String> -TargetVaultName <String> -SubscriptionId <String> -TargetSubscriptionId <String> -Force -SkipSecrets <String>, <String>, <String>
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$VaultName,

    [Parameter(Mandatory = $true)]
    [string]$TargetVaultName,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$TargetSubscriptionId,

    [Parameter(Mandatory = $false)]
    [string[]]$Name,

    [Parameter(Mandatory = $false)]
    [string[]]$SkipSecrets,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$Runbook
)

$InformationPreference = 'Continue'

function aaLogin {
    Disable-AzContextAutosave -Scope Process
    $AzureContext = (Connect-AzAccount -Identity).context
    $AzureContext = Set-AzContext -SubscriptionId $subscriptionId -DefaultProfile $AzureContext
}
function Set-AzSubscription {

    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    # Set Context to correct Subscription.
    Set-AzContext -Subscription $SubscriptionId

    # Check Subscription Context
    $subCheck = (Get-AzContext).Subscription.Id
    try {
        if ($subCheck -ne $SubscriptionId) {
            Write-Error "Error: Subscription Mismatch, check context!"
            exit 1
        }
    }
    catch {
        Write-Error "Error: $($_.Exception)"
    }
}
function Disable-KeyVaultFirewall {

    param (
        [Parameter(Mandatory = $true)]
        [string]$VaultName
    )

    $vault = Get-AzKeyVault -VaultName $VaultName -ErrorAction SilentlyContinue
    $firewallDefaultAction = $vault.NetworkAcls.DefaultAction
    $firewallEnabled = $firewallDefaultAction -eq 'Deny'
    if ($firewallEnabled) {
        $null = Update-AzKeyVaultNetworkRuleSet -VaultName $VaultName -DefaultAction 'Allow'
    }
}
try {
    if ($Runbook) {
        aaLogin
    }
    # Set AzContext and make sure FireWall is set to "Allowed" to be able to access secrets
    Set-AzSubscription -SubscriptionId $SubscriptionId
    Disable-KeyVaultFirewall -VaultName $VaultName
    Disable-KeyVaultFirewall -VaultName $TargetVaultName

    #Check if Source and Target Vaults exists
    $srcVault = Get-AzKeyVault -VaultName $VaultName -ErrorAction SilentlyContinue
    $dstVault = Get-AzKeyVault -VaultName $TargetVaultName -ErrorAction SilentlyContinue

    # Skip Secrets form Copy operation if specified in $SkipSecrets Parameter
    if ($SkipSecrets) {
        $exclusionList = @()
        $exclusionList += $SkipSecrets
    }
    if ($srcVault -and $dstVault) {
        # Run this block if no input in parameter $Name specified
        if (!$Name) {
            if ($SkipSecrets) {
                $Name = (Get-AzKeyVaultSecret -VaultName $VaultName).Name | Where-Object { -not $exclusionList.Contains("$($_)") } | Sort-Object
            }
            else {
                $Name = (Get-AzKeyVaultSecret -VaultName $VaultName).Name | Sort-Object
            }
        }
        foreach ($n in $Name) {
            # Get key vault secret
            $srcSecretValue = Get-AzKeyVaultSecret -VaultName $VaultName -Name $n -AsPlainText -ErrorAction SilentlyContinue
            $srcSecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $n -ErrorAction SilentlyContinue

            # Set Destination Subscription Context if available
            if ($TargetSubscriptionId) {
                $null = Set-AzContext -SubscriptionId $TargetSubscriptionId
            }
            # Compare Source and Destination Secret Values
            <# Only copy if value of secret and existing destination do not match.
            We need to convert secrets to plain text to be able to compare secret values in different keyvaults.
            This is needed when copying/updating/backing_up secrets with a powershell script.
            Default action of PowerShell command "Set-AzKeyVaultSecret" is creating new versions even when secrets have same SecretValue.
            This is why we are comparing secrets, to be able to prevent new sercret versions with exact same secret values.#>
            $dstSecretValue = Get-AzKeyVaultSecret -VaultName $TargetVaultName -Name $n -AsPlainText -ErrorAction SilentlyContinue
            if ($srcSecretValue -ne $dstSecretValue) {
                $SecretValue = $srcSecretValue | ConvertTo-SecureString -AsPlainText -Force
                $Copy = Set-AzKeyVaultSecret `
                    -VaultName $TargetVaultName `
                    -SecretValue $SecretValue `
                    -Name $srcSecret.Name `
                    -Expires $srcSecret.Expires `
                    -ContentType $srcSecret.ContentType `
                    -Tag $srcSecret.Tags `
                    -Confirm:(!$Force)
                Write-Output "Successfully copied secret name '$($Copy.Name)' with id '$($Copy.Id)'"
            }
            else {
                Write-Output "Secret Name '$($srcSecret.Name)' with id '$($srcSecret.id)'already existing in destination vault"
            }
        }
    }
}
catch {
    Write-Error "Error: $($_.Exception)"
}
finally {
    # Void secrets
    $srcSecretValue = ""
    $dstSecretValue = ""
    $SecretValue = ""
    # Switch Source Vault Firewall back to Deny if default action was 'Deny'
    if ($srcFirewallEnabled) {
        $null = Update-AzKeyVaultNetworkRuleSet -VaultName $VaultName -DefaultAction 'Deny'
    }
    # Switch Destination Vault Firewall back to Deny if default action was 'Deny'
    if ($dstFirewallEnabled) {
        $null = Update-AzKeyVaultNetworkRuleSet -VaultName $TargetVaultName -DefaultAction 'Deny'
    }
}
