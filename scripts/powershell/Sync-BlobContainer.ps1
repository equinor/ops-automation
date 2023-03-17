<#
  .SYNOPSIS
  Main purpose of this script is to replace existing “Destination” blob container with new Container that have same name as the old one and to Copy all blobs from Source  Container to Destination.  In this we will replace all blobs in destination with blobs from source.
  This is useful when you need to sync blob content between different environments. For example, to keep non-prod environments updated with production.
  It can also be used as a disaster recovery program to re-create production Container if needed.

  It checks if source storage/container and destination storage are available before it continues to run.
  If destination container available, it first removes it and re-create it.
  If no destination container available, script creates container with name given i Parameter "sourceContainerName".
  Then script checks if destination container is empty before running AzCopy to Copy all blobs from source to destination.
  At the end, script count source and destination blobs to see if equal number of blobs are available in source and destination.
  Be aware of that last step that checks number of blobs can fail due to creation of new blobs while script is still running.

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

  .PARAMETER srcRg
  Specifies the Source Resource Group Name.

  .PARAMETER dstRg
  Specifies the Destination Resource Group Name.

  .PARAMETER sourceStorageName
  Specifies the name of source Storage Account.

  .PARAMETER destStorageName
  Specifies the name of destination Storage Account.

  .PARAMETER sourceContainerName
  Specifies the name of source Storage Account Container.

  .PARAMETER destContainerName
  Specifies the name of destination Storage Account Container.

  .EXAMPLE
  $scriptParams = @{
    subscriptionId = "SubscriptionId"
    srcRg = "rg_name"
    dstRg = "rg_name"
    sourceStorageName = "storage_name"
    destStorageName = "storage_name"
    sourceContainerName = "container_name"
    destContainerName = "container_name"
  }
.\CopyAndReplaceBlobs.ps1 @scriptParams
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$subscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$srcRg,

    [Parameter(Mandatory = $true)]
    [string]$dstRg,

    [Parameter(Mandatory = $true)]
    [string]$sourceStorageName,

    [Parameter(Mandatory = $true)]
    [string]$destStorageName,

    [Parameter(Mandatory = $true)]
    [string]$sourceContainerName,

    [Parameter(Mandatory = $true)]
    [string]$destContainerName
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

# Get Storage Accounts
$sourceStorage = Get-AzStorageAccount -ResourceGroupName $srcRg | Where-Object StorageAccountName -eq $sourceStorageName -ErrorAction SilentlyContinue
$destStorage = Get-AzStorageAccount -ResourceGroupName $dstRg | Where-Object StorageAccountName -eq $destStorageName -ErrorAction SilentlyContinue
# Get Containers
$SourceContainer = $sourceStorage | Get-AzStorageContainer -Name $sourceContainerName -ErrorAction SilentlyContinue
$DestinationContainer = $destStorage | Get-AzStorageContainer -Name $destContainerName -ErrorAction SilentlyContinue

# Proceed with program only if required resources are present
if ($sourceStorage -and $destStorage -and $SourceContainer) {
    if ($DestinationContainer) {
        # Remove destination container if destination container exists
        Write-Information "Removing Existing Destination Container in Destination Storage Account"
        $DestinationContainer | Remove-AzStorageContainer -Force
        while ( $destStorage | Get-AzStorageContainer  -Name $destContainerName -ErrorAction SilentlyContinue ) {
            Write-Information "Waiting for destination container to be removed: $($WaitTime)"
            Start-Sleep -Seconds 5
            $WaitTime += 5
        }
        Write-Information "Destination Container removed!"
        Write-Information "Waiting for 60 seconds before re-creating container again."
        Start-Sleep -Seconds 60

        # Re-create container in destination storage account
        $destStorage | New-AzStorageContainer -Name $destContainerName
        while (!( $destStorage | Get-AzStorageContainer -Name $destContainerName -ErrorAction SilentlyContinue )) {
            Write-Information "Waiting for destination container to be available: $($WaitTime)"
            Start-Sleep -Seconds 5
            $WaitTime += 5
        }
        Write-Information "Destination Container available!"
    }
    elseif (!$DestinationContainer) {
        # Re-create container in destination storage account
        Write-Information "No Container found in destination Storage Account, proceeding with creation of new container in destination with name $($destContainerName)"
        $destStorage | New-AzStorageContainer -Name $destContainerName
        Start-Sleep -Seconds 10
        # Check if destination container is created. Pause until available.
        while (!( $destStorage | Get-AzStorageContainer -Name $destContainerName -ErrorAction SilentlyContinue )) {
            Write-Information "Waiting for destination container to be available: $($WaitTime)"
            Start-Sleep -Seconds 5
            $WaitTime += 5
        }
        Write-Information "Destination Container available!"
    }

    $dstContainer = $destStorage | Get-AzStorageContainer -Name $destContainerName
    $dstContainer = $dstContainer | Get-AzStorageBlob
    $existingBlobs = $dstContainer.Length
    if ($existingBlobs -eq 0) {
        # Copy all Blobs from Source to Destination Container
        Write-Information "No blobs found in destination. Proceeding with copy operation from Source to Destination Container. This may take a while..."
        $source = "https://$sourceStorageName.blob.core.windows.net/$sourceContainerName/*"
        $destination = "https://$destStorageName.blob.core.windows.net/$destContainerName"
        azcopy copy $source $destination --recursive --overwrite=ifsourcenewer
    }
    else {
        Write-Information "Blobs found in destination. Skipping copy operation. Number of existing Blobs in Destination: $($existingBlobs)"
    }

    # Count Source Blobs
    $srcContainer = $sourceStorage | Get-AzStorageContainer -Name $sourceContainerName
    $srcContainer = $srcContainer | Get-AzStorageBlob
    $srcBlobNumber = $srcContainer.Length
    # Count Destination Blobs
    $dstContainer = $destStorage | Get-AzStorageContainer -Name $destContainerName
    $dstContainer = $dstContainer | Get-AzStorageBlob
    $dstBlobNumber = $dstContainer.Length

    # Compare blobs
    if ($srcBlobNumber -eq $dstBlobNumber) {
        Write-Information "Success! Number of blobs in source and destination container equal."
    }
    else {
        Write-Error "Error! Difference number of source and destination blobs. Please check azcopy logs. `
        Source Container Blobs = $($srcBlobNumber), Target Container Blobs = $($dstBlobNumber) "
    }
}
else {
    Write-Error "Cannot find one or more of required resources. Please check input parameters and make sure resources exists in the portal before running again."
    Write-Information "Exiting program."
}
