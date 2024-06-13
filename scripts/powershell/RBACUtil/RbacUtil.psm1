function Test-RbacJson {
  [CmdletBinding()]
  param (
    [Parameter(
      Position = 1,
      Mandatory = $true,
      ValueFromPipeline = $true
    )]
    [string]$ConfigFile
  )

  if (Test-Path -Path $configFile -PathType Leaf) {
    $configJson = Get-Content -Path $ConfigFile -Raw
  }
  else {
    throw "Configuration file '$ConfigFile' does not exist."
  }

  if ($null -eq $configJson) {
    throw "Configuration JSON is empty."
  }

  $schemaFile = "$PSScriptRoot\rbac.schema.json"
  if (Test-Json -Json $configJson -SchemaFile $schemaFile -ErrorAction SilentlyContinue -ErrorVariable JsonError) {
    return $true
  }
  else {
    #Write-Output "Configuration JSON is invalid: $($JsonError[0].ToString())"
    return $false
  }
}

function getRbacRolesConfig {
  [CmdletBinding()]
  param (
    [Parameter(
      Position = 1,
      Mandatory = $true,
      ValueFromPipeline = $true
    )]
    [string]
    $ConfigFile
  )
  end {
    if (-not (Test-RbacJson -ConfigFile $ConfigFile)) {
      throw "Error! JSON not valid!"
    }
    $configJson = Get-Content $ConfigFile -Raw
    $config = ConvertFrom-Json -InputObject $configJson
    $configRoleAssignments = $config.roleAssignments

    return $configRoleAssignments
  }
}

function Compare-RbacJson {
  [CmdletBinding()]
  param(
    # Input file
    [Parameter(
      Position = 1,
      Mandatory = $true,
      ValueFromPipeline = $true
    )]
    [string]
    $ConfigFile
  )
  if (-not (Test-RbacJson -ConfigFile $ConfigFile)) {
    throw "Error! JSON not valid!"
  }
  $subscriptionId = (Get-AzContext).Subscription.Id
  $parentScope = "/subscriptions/$subscriptionId"

  $configRoleAssignments = getRbacRolesConfig -ConfigFile $ConfigFile

  # Get existing role assignments in Azure. Exclude CDC role assignments
  $azRoleAssignments = Get-AzRoleAssignment -Scope $parentScope | Where-Object { $_.scope -match "^$parentScope/*" -and $_.displayName -notlike "Defender for Containers provisioning*" }

  # Compare configuration to Azure
  $Properties = "DisplayName", "ObjectId", "RoleDefinitionName", "RoleDefinitionId", "Scope"
  $comparison = Compare-Object -ReferenceObject $configRoleAssignments -DifferenceObject $azRoleAssignments -Property $properties -IncludeEqual

  $inConfig = $comparison | Where-Object { $_.SideIndicator -eq "<=" }
  $inAzure = $comparison | Where-Object { $_.SideIndicator -eq "=>" }
  $inBoth = $comparison | Where-Object { $_.SideIndicator -eq "==" }

  $inAzureJSON = ($inAzure | ConvertTo-json)
  $inConfigJSON = ($inConfig | ConvertTo-json)
  $inBothJSON = ($inBoth | ConvertTo-json)

  if (!$inAzureJSON) {
    $inAzureJSON = ""
  }
  if (!$inConfigJSON) {
    $inConfigJSON = ""
  }
  if (!$inBothJSON) {
    $inBothJSON = ""
  }

  return $inAzureJSON, $inConfigJSON
}

function Export-RbacJson {
  [CmdletBinding()]
  param (
    #Output file
    [Parameter(
      Position = 1,
      Mandatory = $true,
      ValueFromPipeline = $true
    )]
    [string]$ConfigFile
  )

  if (-not (Test-RbacJson -ConfigFile $ConfigFile)) {
    throw "Error! JSON not valid!"
  }
  
  $subscriptionId = (Get-AzContext).Subscription.Id
  $parentScope = "/subscriptions/$subscriptionId"

  $configRoleAssignments = getRbacRolesConfig -ConfigFile $ConfigFile

  # Get existing role assignments in Azure. Exclude CDC role assignments
  $azRoleAssignments = Get-AzRoleAssignment -Scope $parentScope | Where-Object { ($_.scope -match "^$parentScope/*") -and ($_.displayName -notlike "Defender for Containers provisioning*") }

  # Compare configuration to Azure
  $Properties = "DisplayName", "ObjectId", "RoleDefinitionName", "RoleDefinitionId", "Scope"
  if ($null -ne $configRoleAssignments) {

    # Create new config that contains role assignments that exist in both config and Azure (side indicator "=="), or only Azure (side indicator "=>").
    # Exclude role assignments that are only in config (side indicator "<="), to ensure config matches Azure.
    $newConfigRoleAssignments = Compare-Object -ReferenceObject $configRoleAssignments -DifferenceObject $azRoleAssignments -Property $properties -IncludeEqual |
    Where-Object { $_.SideIndicator -eq "==" -or $_.SideIndicator -eq "=>" } |
    Select-Object -Property $properties

    $json = (@{
        "roleAssignments" = $newConfigRoleAssignments | Select-Object -Property $properties
      } | ConvertTo-Json -Depth 100 )
  }
  else {
    $json = (@{
        "roleAssignments" = $azRoleAssignments | Select-Object -Property $properties
      } | ConvertTo-Json -Depth 100)
  }
  $json | Set-Content -Path $configFile -OutVariable $null
}