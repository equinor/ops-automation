Import-Module "$PSScriptRoot\modules\appRegistrationModules.psm1" -Force

$tenant = " " # Azure tenant ID
$serviceNowReference = " " # Service now reference number

# Script will check if app registration already exists. For the sake of disaster recovery no app should be removed from list below. Here you input the name of you choosing to create App Registrations.
$applicationNames = @(
    ""
    )

# Script will only add, not remove already existing owners. Add the object ID of the user who will be the Owner of the App registrations.
$ownerList = @( 
    ""
    )


new-AppRegistration `
    -ApplicationNames $applicationNames `
    -ServiceNowReference $serviceNowReference `
    -OwnerList $ownerList `
    -Tenant $tenant