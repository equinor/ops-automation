function Export-AzureResourcesMarkdown {
    <#
        .DESCRIPTION
        Export Azure Resources to Markdown using a combination of Azure CLI and ConvertTo-Markdown PS Module.
        Requires ConvertTo-Markdown module. This is part of  PSScriptTools found here: https://github.com/jdhitsolutions/PSScriptTools
        .PARAMETER SubscriptionId
        Subscription ID
        .PARAMETER TenantDomainName
        Tenant Domain Name (what is in front of .onmicrosoft.com in the URL)
        .EXAMPLE
        $domain = "contoso"
        $subId  = "xxx-xxx-xxxx-xxx-xxx"

        # Export to Markdown
        Export-AzureResourcesMarkdown -SubscriptionId $subId -TenantDomainName $domain
    #>
    [CmdletBinding()]
    param (
        [Parameter (Mandatory = $true)][String] $TenantDomainName,
        [Parameter (Mandatory = $true)][String] $SubscriptionId
    )
    # Check current Subscription Context and match against SubscriptionId
    $sub = az account show | ConvertFrom-Json
    if ($sub.id -ne $SubscriptionId) {
        Write-Output "Wrong context"
        exit
    }
    try {
        # Get all resources in subscription
        $resources = az resource list --subscription $subscriptionId | ConvertFrom-Json

        Write-Output "Number of resources found: $($resources.Length)"
        $result = foreach ($resource in $resources | Where-Object { $_.resouceType }) {
            $date = Get-Date -Format "yyyy.MM.dd"
            $resRg = "[$($resource.resourceGroup)](https://portal.azure.com/#@$TenantDomainName.onmicrosoft.com/resource/subscriptions/$subscriptionId/resourceGroups/$($resource.resourceGroup))"
            $idFix = [uri]::EscapeUriString($resource.id)
            $resUrl = "[$($resource.name)](https://portal.azure.com/#@$TenantDomainName.onmicrosoft.com/resource$idFix)"
            $resource | Add-Member -NotePropertyName ResourceName -NotePropertyValue $resUrl
            $resource | Add-Member -NotePropertyName ResourceGroupName -NotePropertyValue $resRg
            $resource | Add-Member -NotePropertyName DateSurveyed -NotePropertyValue $date
            $resource
        }
        $result | Select-Object `
        @{n = "Name"; e = { $_.ResourceName } }, `
        @{n = "Resource Group"; e = { $_.ResourceGroupName } }, `
        @{n = "Location"; e = { $_.location } }, `
        @{n = "Type"; e = { $_.type } }, `
        @{n = "Date Surveyed"; e = { $_.DateSurveyed } }, `
        @{n = "Created Time"; e = { $_.createdTime } }, `
        @{n = "Changed Time"; e = { $_.changedTime } } | Sort-Object "Resource Group" | `
            ConvertTo-Markdown -AsTable -Title "Azure Resources in $($sub.name)" `
            -PreContent "**Subscription Name**: $($sub.name)`n`n**Subscription Id**: $($sub.id)`n`n**Number of resources**: $($resources.Length)`n`n**Last Run**: $date"
    }
    catch {
        Write-Output $_.Exception
        exit
    }
}