<#
  .SYNOPSIS
  Main purpose of this script is to create new App Registrations in Microsoft Entra ID.
  Pre-requisites:
  - Need to install az module before running this script.
    Install-Module az
  - Application Developer PIM activated
  .PARAMETER Tenant
    String containing Tenant ID.
  .PARAMETER ServiceNowReference
    String containing Service Now Referance. To be added in 'Service Management Referance'
  .PARAMETER OwnerList
    Array of owners. Must be Object ID from Azure.
  .PARAMETER ApplicationNames
    Array of display names for the app registrations you want to create.
  .EXAMPLE
    $Tenant = "" # Tenant ID
    $ServiceNowReference = "" # Service Now reference number
    $OwnerList = @(" ")
    $ApplicationNames = @(" ")

    create-AppRegistration `
        -ApplicationNames $ApplicationNames `
        -ServiceNowReference $ServiceNowReference `
        -OwnerList $OwnerList `
        -Tenant $Tenant
#>


function new-AppRegistration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [array]$ApplicationNames,
        [Parameter (Mandatory = $true)]
        [array]$OwnerList,
        [Parameter (Mandatory = $true)]
        [string]$ServiceNowReference,
        [Parameter (Mandatory = $true)]
        [string]$Tenant
        )


    Disconnect-AzAccount # Disconnect any existing session
    Connect-AzAccount -Tenant $Tenant

    #################

    $userName = $(Get-AzAccessToken -ResourceTypeName MSGraph).UserId
    $password = ConvertTo-SecureString -String (Get-AzAccessToken -ResourceTypeName MSGraph).Token -AsPlainText
    $tokenCredObject = New-Object -TypeName PSCredential -ArgumentList($userName, $password)

    foreach ($applicationName in $ApplicationNames) {
        # Check if application already exists
        $endpoint = "https://graph.microsoft.com/beta/applications?`$filter=displayName eq '$applicationName'&`$count=true"
        $application = Invoke-RestMethod -Method GET -Uri $endpoint -Headers @{"Authorization"="Bearer $($tokenCredObject.GetNetworkCredential().Password)";"ConsistencyLevel"="eventual"} -DisableKeepAlive -ContentType "application/json"
        if ($application."@odata.count" -ne 0) {
            write-host "$applicationName already exists. Skipping!"
            continue #exits the loop to avoid duplicate app registrations.
        }

        # Application meta data body
        $jsonbody = @{
            displayname = $applicationName
            serviceManagementReference = $ServiceNowReference
            description = "App registration for $applicationName"
            notes = "Created by automation script in $applicationName."
            signInAudience = "AzureADMyOrg"
        } | ConvertTo-Json

        # Create application
        $endpoint = "https://graph.microsoft.com/beta/applications"
        $graphData = Invoke-RestMethod -Method POST -Uri $endpoint -Headers @{"Authorization"="Bearer $($tokenCredObject.GetNetworkCredential().Password)"} -DisableKeepAlive -UseBasicParsing -Body $jsonBody -ContentType "application/json"


        Start-Sleep -Seconds 5

        # Create SPN
        $spnBody = @{
            appId = $graphData.appId
        } | ConvertTo-Json

        $endpoint = "https://graph.microsoft.com/beta/servicePrincipals"
        $spnData = Invoke-RestMethod -Method POST -Uri $endpoint -Headers @{"Authorization"="Bearer $($tokenCredObject.GetNetworkCredential().Password)"} -DisableKeepAlive -UseBasicParsing -Body $spnBody -ContentType "application/json"

        Start-Sleep -Seconds 5

        # Add Owner on application
        Foreach ($u in $OwnerList) {
            $ownerJson = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$u"
            } | ConvertTo-Json

            try {
                Write-Output "Adding owner: $u on application: $($graphdata.displayName)"
                $endpoint = "https://graph.microsoft.com/v1.0/applications/$($graphdata.Id)/owners/`$ref"
                Invoke-RestMethod -Method POST -Uri $endpoint -Headers @{"Authorization"="Bearer $($tokenCredObject.GetNetworkCredential().Password)"} -DisableKeepAlive -UseBasicParsing -Body $ownerJson -ContentType "application/json"
            }
            catch {
                Write-Output "Couldn't add owner, $u may already be owner of application: $($graphdata.displayName)"
            }
            Start-Sleep -Seconds 2
        }

        # Add Owner ON SPN
        Foreach ($u in $OwnerList) {

            $ownerJson = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$u"
            } | ConvertTo-Json

            try {
                Write-Output "Adding owner: $u on serviceprincipal: $($spnData.displayName)"
                $endpoint = "https://graph.microsoft.com/v1.0/servicePrincipals/$($spnData.Id)/owners/`$ref"
                Invoke-RestMethod -Method POST -Uri $endpoint -Headers @{"Authorization"="Bearer $($tokenCredObject.GetNetworkCredential().Password)"} -DisableKeepAlive -UseBasicParsing -Body $ownerJson -ContentType "application/json"
            }
            catch {
                Write-Output "Couldn't add owner, $u may already be owner of serviceprincipal: $($spnData.displayName)"
            }
            Start-Sleep -Seconds 2
        }
        return "$applicationName Created!"
        Start-Sleep -Seconds 2
    }
}