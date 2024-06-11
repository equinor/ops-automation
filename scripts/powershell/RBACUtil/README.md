# RBAC

PowerShell script which checks RBAC assignments for a given subscription.

## Prerequisites

- Azure PowerShell: `Install-Module Az`

## Usage

1. Open PowerShell.

1. Login to Azure:

    ```powershell
    Connect-AzAccount
    ```

1. Set active Azure subscription:

    ```powershell
    Set-AzContext -Subscription "<SUBSCRIPTION_NAME_OR_ID>"
    ```

1. Configure role assignments in a file - Use `rbac.json` as template.

1. Run script `rbac.ps1`:

    ```powershell
    ./rbac.ps1 -configFile <configFile name> -Mode <Compare|ExportToJson|ImportFromJson>
    ```

## `Mode` switch

- Compare: Compares role assignments in subscription to the contents of the config file. Lists the ones being different.
- ExportToJson: Exports role assignments from Azure into the config file. Will append.
- ImportFromJson: Imports non-existant role assignments to Azure. Will fail if role assignment exists.

## Config spec

As defined in `rbac.schema.json`:

```json
{
  "roleAssignments": [
    {
      "displayName": "string",
      "objectId": "string",
      "roleDefinitionId": "string",
      "roleDefinitionName": "string",
      "scope": "string",
    }
  ]
}
```

Example config:

```json
{
  "roleAssignments": [
    {
      "displayName": "John Doe",
      "objectId": "00000000-0000-0000-0000-000000000000",
      "roleDefinitionId": "00000000-0000-0000-0000-000000000000",
      "roleDefinitionName": "Example Administrator",
      "scope": "/subscriptions/<SUBSCRIPTION_ID>"
    },
    {
      "displayName": "Jane Doe",
      "objectId": "00000000-0000-0000-0000-000000000000",
      "roleDefinitionId": "00000000-0000-0000-0000-000000000000",
      "roleDefinitionName": "Example Administrator",
      "scope": "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/example-rg",
    }
  ]
}
```

## Features (will be subject to change)

- [X] Create role assignments
- [X] View differences between environment and config