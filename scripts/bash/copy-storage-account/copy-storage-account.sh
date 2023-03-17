#!/bin/bash
#
# Copies a source Azure storage account to a destination storage account using AzCopy.
# Arguments:
#   Source storage account name.
#   Destination storage account name.

set -eu

src_account_name=$1
dest_account_name=$2

azcopy cp "https://$src_account_name.blob.core.windows.net/" "https://$dest_account_name.blob.core.windows.net/" --recursive=true
