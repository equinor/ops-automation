param (
  [Parameter(Mandatory = $true)]
  [string]$configFile,

  [Parameter(
    Mandatory = $true)]
  [ValidateSet("Compare", "ImportFromJson", "ExportToJson")]
  [string]$Mode
)

function verifyJson {
  if (Test-Path -Path $configFile -PathType Leaf) {
    $configJson = Get-Content -Path $configFile -Raw
  }
  else {
    throw "Configuration file '$configFile' does not exist."
  }

  if ($null -eq $configJson) {
    throw "Configuration JSON is empty."
  }

  $schemaFile = "$PSScriptRoot\rbac.schema.json"
  if (Test-Json -Json $configJson -SchemaFile $schemaFile -ErrorAction SilentlyContinue -ErrorVariable JsonError) {
    $Script:config = ConvertFrom-Json -InputObject $configJson
  }
  else {
    throw "Configuration JSON is invalid: $($JsonError[0].ToString())"
  }
}

function exportConfig {
  $subscriptionId = (Get-AzContext).Subscription.Id
  $parentScope = "/subscriptions/$subscriptionId"

  $configRoleAssignments = $config.roleAssignments

  # Get existing role assignments in Azure. Exclude CDC role assignments
  $azRoleAssignments = Get-AzRoleAssignment -Scope $parentScope | Where-Object { ($_.scope -match "^$parentScope/*") -and ($_.displayName -notlike "Defender for Containers provisioning*") }

  # Compare configuration to Azure
  $Properties = "DisplayName", "ObjectId", "RoleDefinitionName", "RoleDefinitionId", "Scope"
  if ($null -ne $configRoleAssignments) {
    $comparison = Compare-Object -ReferenceObject $configRoleAssignments -DifferenceObject $azRoleAssignments -Property $properties -IncludeEqual
  

    $inConfig = $comparison | Where-Object { $_.SideIndicator -eq "<=" }
    $inAzure = $comparison | Where-Object { $_.SideIndicator -eq "=>" }
    $inBoth = $comparison | Where-Object { $_.SideIndicator -eq "==" }

    # $newConfig = $configRoleAssignments + $inAzure

    # Create new config that contains role assignments that exist in both config and Azure (side indicator "=="), or only Azure (side indicator "=>").
    # Exclude role assignments that are only in config (side indicator "<="), to ensure config matches Azure.
    $newConfigRoleAssignments = Compare-Object -ReferenceObject $configRoleAssignments -DifferenceObject $azRoleAssignments -Property $properties -IncludeEqual |
    Where-Object { $_.SideIndicator -eq "==" -or $_.SideIndicator -eq "=>" } |
    Select-Object -Property $properties

    # $newConfigRoleAssignments | Where-Object { $_.scope -eq '/subscriptions/${{ SUBSCRIPTION_ID }}' }
    
    @{
      "roleAssignments" = $newConfigRoleAssignments | Select-Object -Property $properties
    } | ConvertTo-Json -Depth 100 | Set-Content -Path $configFile

    $newConfigRoleAssignments.objectId.Count
  }
  else {
    @{
      "roleAssignments" = $azRoleAssignments | Select-Object -Property $properties
    } | ConvertTo-Json -Depth 100 | Set-Content -Path $configFile
  }
}

function compareConfig {
  $subscriptionId = (Get-AzContext).Subscription.Id
  $parentScope = "/subscriptions/$subscriptionId"

  $configRoleAssignments = $config.roleAssignments

  # Get existing role assignments in Azure. Exclude CDC role assignments
  $azRoleAssignments = Get-AzRoleAssignment -Scope $parentScope | Where-Object { $_.scope -match "^$parentScope/*" -and $_.displayName -notlike "Defender for Containers provisioning*" }

  # Compare configuration to Azure
  $Properties = "DisplayName", "ObjectId", "RoleDefinitionName", "RoleDefinitionId", "Scope"
  $comparison = Compare-Object -ReferenceObject $configRoleAssignments -DifferenceObject $azRoleAssignments -Property $properties -IncludeEqual

  $inConfig = $comparison | Where-Object { $_.SideIndicator -eq "<=" }
  $inAzure = $comparison | Where-Object { $_.SideIndicator -eq "=>" }
  $inBoth = $comparison | Where-Object { $_.SideIndicator -eq "==" }

  Write-Host "Elements in config only:"
  Write-Host "------------------------"
  if ($null -ne $inConfig) {
    $inConfig | Format-Table DisplayName, roleDefinitionName, scope
  }
  else {
    Write-Host "`nNone!`n"
  }

  Write-Host "Elements in Azure only:"
  Write-Host "-----------------------"
  if ($null -ne $inAzure) {
    $inAzure | Format-Table DisplayName, RoleDefinitionName, Scope
  }
  else {
    Write-Host "`nNone!`n"
  }
}

function importconfig {
  $subscriptionId = (Get-AzContext).Subscription.Id
  $parentScope = "/subscriptions/$subscriptionId"

  $configRoleAssignments = $config.roleAssignments

  # Get existing role assignments in Azure. Exclude CDC role assignments
  $azRoleAssignments = Get-AzRoleAssignment -Scope $parentScope | Where-Object { ($_.scope -match "^$parentScope/*") -and ($_.displayName -notlike "Defender for Containers provisioning*") }

  # Compare configuration to Azure
  $Properties = "DisplayName", "ObjectId", "RoleDefinitionName", "RoleDefinitionId", "Scope"
  if ($null -ne $configRoleAssignments) {
    $comparison = Compare-Object -ReferenceObject $configRoleAssignments -DifferenceObject $azRoleAssignments -Property $properties -IncludeEqual
  
    $inConfig = $comparison | Where-Object { $_.SideIndicator -eq "<=" }

    if ($null -ne $inConfig ) {
      foreach ($assignment in $inConfig) {
        New-AzRoleAssignment -ObjectId $assignment.ObjectId -Scope $assignment.Scope -RoleDefinitionName $assignment.RoleDefinitionName -OutVariable $out
      }
    }
    else {
      Write-Host "Nothing to do!"
    }
  }
}

switch ($Mode) {
  "Compare" {
    verifyJson
    compareConfig
  }

  "ImportFromJson" {
    verifyJson
    importconfig
  }

  "ExportToJson" {
    exportConfig
  }
}