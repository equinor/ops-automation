<#
  .SYNOPSIS
  Main purpose of this script is to replace existing “Destination” blob container with new Container that have same name as the old one and to Copy all blobs from Source  Container to Destination.
  This is useful when you need to sync blob content between different environments. For example, to keep non-prod environments updated with production.
  It can also be used as a disaster recovery program to re-create production Container if needed.

  Program checks source and destination storage network rules and makes sure runner's Public IP is added/allowed.
  It checks if source storage/container and destination storage are available before it continues to run.
  If destination container available, it first removes it and re-create it.
  If no destination container available, script creates container with name given i Parameter "sourceContainerName".
  Then script checks if destination container is empty before running AzCopy to Copy all blobs from source to destination.
  At the end, script count source and destination blobs to see if equal number of blobs are available in source and destination.
  Be aware of that last step that checks number of blobs can fail due to creation of new blobs while script is still running.
  Finally it restores the original network settings of source and destination storage.

  Pre-requisites:
  Need to run following before running this script to authenticate to Azure:
  Connect-AzAccount
  azcopy.exe login

  If this script is used in GitHub actions, we strongly recommend using azure/login@v1 action with OIDC.
  As GitHub runners already have installed azcopy, it's just to follow azcopy login as this example:

  $env:AZCOPY_SPA_CLIENT_SECRET= $env:SERVICE_PRINCIPAL_SECRET_VALUE
  azcopy login `
    --service-principal `
    --application-id $env:SERVICE_PRINCIPAL_CLIENT_ID `
    --tenant-id $env:TENANT_ID

  .PARAMETER subscriptionId
  Specifies the ID of Azure Subscription.

  .PARAMETER sourceResourceGroup
  Specifies the Source Resource Group Name.

  .PARAMETER destinationResourceGroup
  Specifies the Destination Resource Group Name.

  .PARAMETER sourceStorageName
  Specifies the name of source Storage Account.

  .PARAMETER destinationStorageName
  Specifies the name of destination Storage Account.

  .PARAMETER sourceContainerName
  Specifies the name of source Storage Account Container.

  .PARAMETER destinationContainerName
  Specifies the name of destination Storage Account Container.

  .EXAMPLE
  $scriptParams = @{
    subscriptionId = "SubscriptionId"
    sourceResourceGroup = "rg_name"
    destinationResourceGroup = "rg_name"
    sourceStorageName = "storage_name"
    destinationStorageName = "storage_name"
    sourceContainerName = "container_name"
    destinationContainerName = "container_name"
  }
.\Sync-AadBlobContainer.ps1 @scriptParams
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$sourceResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$destinationResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$sourceStorageName,

    [Parameter(Mandatory = $true)]
    [string]$destinationStorageName,

    [Parameter(Mandatory = $true)]
    [string]$sourceContainerName,

    [Parameter(Mandatory = $true)]
    [string]$destinationContainerName
)

$InformationPreference = 'Continue'

# Set/Check Subscription Context
Set-AzContext -Subscription $subscriptionId
$subCheck = (Get-AzContext).Subscription.Id
try {
    if ($subCheck -ne $subscriptionId) {
        Write-Error "Error: Subscription Mismatch, check context!"
        exit 1
    }
    else {
        Write-Information "Correct Subscription! Proceeding with program."
    }
}
catch {
    Write-Error "Error: $($_.Exception)"
}

try {
    # Get runner Public IP
    $myIp = Invoke-RestMethod http://ipinfo.io/json | Select-Object -ExpandProperty IP
    if (!$myIp) {
        Write-Error "No Public IP found. Exiting program"
        Break
    }

    # Check Source Storage Network Rules
    $sourceStorage = Get-AzStorageAccount -StorageAccountName $sourceStorageName -ResourceGroupName $sourceResourceGroup
    $sourceOriginalDefaultAction = $sourceStorage.NetworkRuleSet.DefaultAction
    $sourceOriginalPublicNetworkAccess = $sourceStorage.PublicNetworkAccess
    if ($sourceStorage.NetworkRuleSet.DefaultAction -eq "Deny" -and $sourceStorage.PublicNetworkAccess -eq "Disabled") {
        Write-Information "Enabling Public Network Access on source storage account name '$($sourceStorageName)'!"
        $null = Set-AzStorageAccount -ResourceGroupName $sourceResourceGroup -Name $sourceStorageName -PublicNetworkAccess Enabled
        Write-Information "Setting Public Network Access default action to deny on source storage account name '$($sourceStorageName)'!"
        $null = Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $sourceResourceGroup -Name $sourceStorageName -DefaultAction Deny
        Write-Information "Adding current runners Public IP to Storage Firewall on source storage account name '$($sourceStorageName)'"
        $null = Add-AzStorageAccountNetworkRule -ResourceGroupName $sourceResourceGroup -StorageAccountName $sourceStorageName -IPAddressOrRange $myIp
        Write-Information "Waiting for 5 seconds."
        Start-Sleep -Seconds 5
        # List allowd IP's and check if runner PIP is added
        $allowedIPs = (Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $sourceResourceGroup -StorageAccountName $sourceStorageName).IpRules.IPAddressOrRange
        if ($allowedIPs -contains $myIp) {
            Write-Information "Successfully added runner PIP to firewall on source storage account name '$($sourceStorageName)'. Proceeding with script"
        }
        elseif ($allowedIPs -notcontains $myIp) {
            Write-Information "Cannot Find Runners PIP in Firwall enabled list on source storage account name '$($sourceStorageName)'. Please verify runners PIP is added before triggering script again."
            Write-Information "Exiting If Statement"
            Break
        }
    }
    elseif ($sourceStorage.NetworkRuleSet.DefaultAction -eq "Deny" -and $sourceStorage.PublicNetworkAccess -eq "Enabled") {
        Write-Information "Adding current runners Public IP to Storage Firewall on source storage account name '$($sourceStorageName)'"
        $null = Add-AzStorageAccountNetworkRule -ResourceGroupName $sourceResourceGroup -StorageAccountName $sourceStorageName -IPAddressOrRange $myIp
        Write-Information "Waiting for 5 seconds."
        Start-Sleep -Seconds 5
        # List allowd IP's and check if runner PIP is added
        $allowedIPs = (Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $sourceResourceGroup -StorageAccountName $sourceStorageName).IpRules.IPAddressOrRange
        if ($allowedIPs -contains $myIp) {
            Write-Information "Successfully added runner PIP to firewall on source storage account name '$($sourceStorageName)'. Proceeding with script"
        }
        elseif ($allowedIPs -notcontains $myIp) {
            Write-Information "Cannot Find Runners PIP in Firwall enabled list on source storage account name '$($sourceStorageName)'. Please verify runners PIP is added before triggering script again."
            Write-Information "Exiting If Statement"
            Break
        }
    }
    elseif ($sourceStorage.NetworkRuleSet.DefaultAction -eq "Allow" -and $sourceStorage.PublicNetworkAccess -eq "Enabled") {
        Write-Information "Public network access already allowed  on source storage account name '$($sourceStorageName)'. Proceeding with program."
    }

    # Check Destination Storage Network Rules
    $destinationStorage = Get-AzStorageAccount -StorageAccountName $destinationStorageName -ResourceGroupName $destinationResourceGroup
    $destinationOriginalDefaultAction = $destinationStorage.NetworkRuleSet.DefaultAction
    $destinationOriginalPublicNetworkAccess = $destinationStorage.PublicNetworkAccess
    if ($destinationStorage.NetworkRuleSet.DefaultAction -eq "Deny" -and $destinationStorage.PublicNetworkAccess -eq "Disabled") {
        Write-Information "Enabling Public Network Access on destination storage account name '$($destinationStorageName)'!"
        $null = Set-AzStorageAccount -ResourceGroupName $destinationResourceGroup -Name $destinationStorageName -PublicNetworkAccess Enabled
        Write-Information "Setting Public Network Access default action to deny on destination storage account name '$($destinationStorageName)'!"
        $null = Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $destinationResourceGroup -Name $destinationStorageName -DefaultAction Deny
        Write-Information "Adding current runners Public IP to Storage Firewall on destination storage account name '$($destinationStorageName)'"
        $null = Add-AzStorageAccountNetworkRule -ResourceGroupName $destinationResourceGroup -StorageAccountName $destinationStorageName -IPAddressOrRange $myIp
        Write-Information "Waiting for 5 seconds."
        Start-Sleep -Seconds 5
        # List allowd IP's and check if runner PIP is added
        $allowedIPs = (Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $destinationResourceGroup -StorageAccountName $destinationStorageName).IpRules.IPAddressOrRange
        if ($allowedIPs -contains $myIp) {
            Write-Information "Successfully added runner PIP to firewall on destination storage account name '$($destinationStorageName)'. Proceeding with script"
        }
        elseif ($allowedIPs -notcontains $myIp) {
            Write-Information "Cannot Find Runners PIP in Firwall enabled list on destination storage account name '$($destinationStorageName)'. Please verify runners PIP is added before triggering script again."
            Write-Information "Exiting If Statement"
            Break
        }
    }
    elseif ($destinationStorage.NetworkRuleSet.DefaultAction -eq "Deny" -and $destinationStorage.PublicNetworkAccess -eq "Enabled") {
        Write-Information "Adding current runners Public IP to Storage Firewall on destination storage account name '$($destinationStorageName)'"
        $null = Add-AzStorageAccountNetworkRule -ResourceGroupName $destinationResourceGroup -StorageAccountName $destinationStorageName -IPAddressOrRange $myIp
        Write-Information "Waiting for 5 seconds."
        Start-Sleep -Seconds 5
        # List allowd IP's and check if runner PIP is added
        $allowedIPs = (Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $destinationResourceGroup -StorageAccountName $destinationStorageName).IpRules.IPAddressOrRange
        if ($allowedIPs -contains $myIp) {
            Write-Information "Successfully added runner PIP to firewall on destination storage account name '$($destinationStorageName)'. Proceeding with script"
        }
        elseif ($allowedIPs -notcontains $myIp) {
            Write-Information "Cannot Find Runners PIP in Firwall enabled list on destination storage account name '$($destinationStorageName)'. Please verify runners PIP is added before triggering script again."
            Write-Information "Exiting If Statement"
            Break
        }
    }
    elseif ($destinationStorage.NetworkRuleSet.DefaultAction -eq "Allow" -and $destinationStorage.PublicNetworkAccess -eq "Enabled") {
        Write-Information "Public network access already Allowed on destination storage account name '$($destinationStorageName)'. Proceeding with program."
    }

    if($sourceOriginalDefaultAction -eq "Deny" -or $destinationOriginalDefaultAction -eq "Deny" -or $sourceOriginalPublicNetworkAccess -eq "Disabled" -or $destinationOriginalPublicNetworkAccess -eq "Disabled"){
        Write-Information "Setting program to sleep 10 seconds..."
        Start-Sleep -Seconds 10
    }


    # Source Storage, Context, Container and Blobs
    $sourceStorage = Get-AzStorageAccount -ResourceGroupName $sourceResourceGroup | Where-Object StorageAccountName -eq $sourceStorageName -ErrorAction SilentlyContinue
    $SourceContext = New-AzStorageContext -StorageAccountName $sourceStorageName -UseConnectedAccount -ErrorAction SilentlyContinue
    $SourceContainer = Get-AzStorageContainer -Context $SourceContext -Container $sourceContainerName -ErrorAction SilentlyContinue

    # Destination Storage, Context, Container and Blobs
    $destinationStorage = Get-AzStorageAccount -ResourceGroupName $destinationResourceGroup | Where-Object StorageAccountName -eq $destinationStorageName -ErrorAction SilentlyContinue
    $DestinationContext = New-AzStorageContext -StorageAccountName $destinationStorageName -UseConnectedAccount -ErrorAction SilentlyContinue
    $DestinationContainer = Get-AzStorageContainer -Context $DestinationContext -Container $destinationContainerName -ErrorAction SilentlyContinue

    # Proceed with program only if required resources are present
    if ($sourceStorage -and $destinationStorage -and $SourceContainer) {
        if ($DestinationContainer) {
            # Remove destination container if destination container exists
            Write-Information "Removing Existing Destination Container  on destination storage account name '$($destinationStorageName)'"
            $DestinationContainer | Remove-AzStorageContainer -Force
            while ( Get-AzStorageContainer -Context $DestinationContext -Container $destinationContainerName -ErrorAction SilentlyContinue ) {
                Write-Information "Waiting for destination container to be removed: $($WaitTime)"
                Start-Sleep -Seconds 5
                $WaitTime += 5
            }
            Write-Information "Destination Container '$($destinationContainerName)' removed!"
            Write-Information "Waiting for 60 seconds before re-creating container again."
            Start-Sleep -Seconds 60

            # Re-create container in destination storage account
            New-AzStorageContainer -Name $destinationContainerName -Context $DestinationContext
            while (!( Get-AzStorageContainer -Context $DestinationContext -Container $destinationContainerName -ErrorAction SilentlyContinue )) {
                Write-Information "Waiting for destination container to be available: $($WaitTime)"
                Start-Sleep -Seconds 5
                $WaitTime += 5
            }
            Write-Information "Destination Container available!"
        }
        elseif (!$DestinationContainer) {
            # Re-create container in destination storage account
            Write-Information "No Container found in destination Storage Account, proceeding with creation of new container in destination with name $($destinationContainerName)"
            New-AzStorageContainer -Name $destinationContainerName -Context $DestinationContext
            Start-Sleep -Seconds 10
            # Check if destination container is created. Pause until available.
            while (!( Get-AzStorageContainer -Context $DestinationContext -Container $destinationContainerName -ErrorAction SilentlyContinue )) {
                Write-Information "Waiting for destination container to be available: $($WaitTime)"
                Start-Sleep -Seconds 5
                $WaitTime += 5
            }
            Write-Information "Destination Container available!"
        }

        $DestinationBlobs = Get-AzStorageBlob -Context $DestinationContext -Container $destinationContainerName -ErrorAction SilentlyContinue
        $DestinationBlobs = $DestinationBlobs.Length
        if ($DestinationBlobs -eq 0) {
            # Copy all Blobs from Source to Destination Container
            Write-Information "No blobs found in destination. Proceeding with copy operation from Source to Destination Container. This may take a while..."
            $source = "https://$sourceStorageName.blob.core.windows.net/$sourceContainerName/*"
            $destination = "https://$destinationStorageName.blob.core.windows.net/$destinationContainerName"
            azcopy copy $source $destination --recursive --overwrite=ifsourcenewer
        }
        else {
            Write-Information "Blobs found in destination. Skipping copy operation. Number of existing Blobs in Destination: $($SourceBlobs)"
        }

        $SourceBlobs = Get-AzStorageBlob -Context $SourceContext -Container $sourceContainerName -ErrorAction SilentlyContinue
        $SourceBlobs = $SourceBlobs.Length
        $DestinationBlobs = Get-AzStorageBlob -Context $DestinationContext -Container $destinationContainerName -ErrorAction SilentlyContinue
        $DestinationBlobs = $DestinationBlobs.Length

        # Compare blobs
        if ($SourceBlobs -eq $DestinationBlobs) {
            Write-Information "Success! Number of blobs in source and destination container equal."
        }
        else {
            Write-Error "Error! Difference number of source and destination blobs. Please check azcopy logs. `
        Source Container Blobs = $($SourceBlobs), Target Container Blobs = $($DestinationBlobs) "
        }
    }
}
catch {
    Write-Error "Error: $($_.Exception)"
}
finally {
    # Remove runners Public IP from Source and Destination Storage Network Allowed List

    # Set Source Storage Firewall back to original state
    if ($sourceOriginalPublicNetworkAccess -eq "Disabled") {
        Write-Output "Removing runners Public IP from source storage $($sourceStorageName)"
        $null = Remove-AzStorageAccountNetworkRule -ResourceGroupName $sourceResourceGroup -StorageAccountName $sourceStorageName -IPAddressOrRange $myIp
        Write-Output "Setting Source Storage $($sourceStorageName) PublicNetworkAccess back to state 'Disabled'"
        $null = Set-AzStorageAccount -ResourceGroupName $sourceResourceGroup -Name $sourceStorageName -PublicNetworkAccess Disabled
    }
    elseif ($sourceOriginalDefaultAction -eq "Deny" -and $sourceOriginalPublicNetworkAccess -eq "Enabled") {
        Write-Output "Removing runners Public IP from source storage $($sourceStorageName)"
        $null = Remove-AzStorageAccountNetworkRule -ResourceGroupName $sourceResourceGroup -StorageAccountName $sourceStorageName -IPAddressOrRange $myIp
    }

    # Set Destination Storage Firewall back to original state
    if ($destinationOriginalPublicNetworkAccess -eq "Disabled") {
        Write-Output "Removing runners Public IP from destination storage  '$($destinationStorageName)'"
        $null = Remove-AzStorageAccountNetworkRule -ResourceGroupName $destinationResourceGroup -StorageAccountName $destinationStorageName -IPAddressOrRange $myIp
        Write-Output "Setting Destination Storage '$($destinationStorageName)' PublicNetworkAccess back to state 'Disabled'"
        $null = Set-AzStorageAccount -ResourceGroupName $destinationResourceGroup -Name $destinationStorageName -PublicNetworkAccess Disabled
    }
    elseif ($destinationOriginalDefaultAction -eq "Deny" -and $destinationOriginalPublicNetworkAccess -eq "Enabled") {
        Write-Output "Removing runners Public IP from destination storage '$($destinationStorageName)'"
        $null = Remove-AzStorageAccountNetworkRule -ResourceGroupName $destinationResourceGroup -StorageAccountName $destinationStorageName -IPAddressOrRange $myIp
    }
}