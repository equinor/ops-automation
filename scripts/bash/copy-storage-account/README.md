# Copy storage account

This directory contains a Bash script `copy-storage-account.sh` which copies the blob contents from a source storage account to a destination storage account.

## Prerequisites

- Install [AzCopy v10](https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10#download-azcopy)

    ```bash
    # Download AzCopy archive
    wget https://aka.ms/downloadazcopy-v10-linux

    # Extract archive
    tar -xvf downloadazcopy-v10-linux

    # (Optional) Remove existing AzCopy executable in destination
    sudo rm /usr/bin/azcopy

    # Copy executable to destination
    sudo cp ./azcopy_linux_amd64_*/azcopy /usr/bin/
    ```

- Azure role `Storage Blob Data Reader` at the source storage account scope
- Azure role `Storage Blob Data Contributor` at the destination storage account scope.

## Run copy script

Login to Azure:

```bash
azcopy login
```

Run copy script:

```bash
./scripts/ras-dr/copy-storage-account.sh <SOURCE_STORAGE_ACCOUNT_NAME> <DESTINATION_STORAGE_ACCOUNT_NAME>
```

## Fix authentication issue

When trying to authenticate using AzCopy, you might experience the following issue:

```text
INFO: Scanning...
INFO: Authenticating to destination using Azure AD

failed to perform copy command due to error: no cached token found, please log in with azcopy's login command, required key not available
```

Quick fix:

```bash
keyctl session workaroundSession
```

Now try again.
