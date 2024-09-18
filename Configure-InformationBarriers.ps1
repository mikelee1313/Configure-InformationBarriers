<#
.SYNOPSIS
This script configures Information Barriers (IB) and Address Book Policies in an Office 365 tenant.

.DESCRIPTION
The script performs the following tasks:
1. Prompts the user for the tenant name and the type of policies (Allow or Block).
2. Connects to various Office 365 services including Exchange Online, SharePoint Online, and IPPS.
3. Creates an Address Book Policy to prevent an empty address book.
4. Assigns the new Address Book Policy to all mailboxes.
5. Enables audit logging for the tenant.
6. Applies department attributes to users.
7. Creates organization segments based on departments.
8. Creates Information Barrier Policies based on the selected policy type (Allow or Block).
9. Starts the application of Information Barrier Policies.
10. Enables Information Barriers for SharePoint and OneDrive.
11. Updates existing OneDrive sites with segments.
12. Checks the current state of Information Barriers and retrieves various IB settings.
13. Checks IB compatibility between random users.
14. Retrieves IB settings for users, OneDrive sites, and SharePoint sites.

.PARAMETER TenantName
The name of the Office 365 tenant (e.g., M365x03708457).

.PARAMETER PolicyType
The type of policies to create: 'allow' or 'block'.

.NOTES
Authors: Mike Lee
Date: 9/18/2024
Disclaimer: The sample scripts are provided AS IS without warranty of any kind. 

Microsoft further disclaims all implied warranties including, without limitation, 
any implied warranties of merchantability or of fitness for a particular purpose. 
The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
In no event shall Microsoft, its authors, or anyone else involved in the creation, 
production, or delivery of the scripts be liable for any damages whatsoever 
(including, without limitation, damages for loss of business profits, business interruption, 
loss of business information, or other pecuniary loss) arising out of the use of or inability 
to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.

- The script requires administrative privileges in the Office 365 tenant.
- Some operations may take up to 24 hours to take full effect.
- Ensure that the necessary modules (e.g., ExchangeOnlineManagement, Microsoft.Graph, SharePointPnPPowerShell) are installed and imported.

.EXAMPLE
.\Configure-InformationBarriers.ps1
Prompts the user for the tenant name and policy type, then configures Information Barriers and Address Book Policies accordingly.
#>

#Tenant
$t = Read-Host "What is your tenant name, IE: M365x03708457"  

#Loop to choose Block or Allow Policies
$validInput = $false
$policytype = @()
while (-not $validInput) {
    Write-Host "Do you want Allow or Block Policies?" -ForegroundColor Green
    $policytype = Read-Host "Please enter 'allow' or 'block'"

    if ($policytype -eq "allow" -or $policytype -eq "block") {
        $validInput = $true
    }
    else {
        Write-Host "Invalid input. Please try again."
    }
}


#Connect to Services
Connect-ExchangeOnline
Connect-IPPSSession -UseRPSSession:$false
Connect-SPOService -Url ('https://' + $t + '-admin.sharepoint.com')
#Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Application.ReadWrite.All"


#Create an Address Book Policy for all Mailboxes to prevent Empty Address Book
Write-Host "Adding role 'Address Lists' to 'Organization Management' to allow for Address Book Management with the GA Account" -ForegroundColor Green
New-ManagementRoleAssignment -SecurityGroup "Organization Management" -Role "Address Lists"
Write-Host "Done...." -ForegroundColor Cyan
Write-Host "After adding role 'Address Lists' to 'Organization Management', reconnecting to Exchange Online" -ForegroundColor Yellow


Write-Host "Waiting 1 minute for the change to take effect." -ForegroundColor Green
for ($i = 60; $i -ge 0; $i--) {
    Write-Host "$i seconds remaining"
    Start-Sleep -Seconds 1
}
Write-Host "Done...." -ForegroundColor Cyan

Write-Host "Signing back into Exchange Online to reflect new roles" -ForegroundColor Green
Connect-ExchangeOnline

Write-Host "Creating Address Book Policy" -ForegroundColor Green
#use the current OAB
$oab = Get-OfflineAddressBook 'Default Offline Address Book'
#use the current GAL
$gal = Get-GlobalAddressList 'Default Global Address List'

#Create new Address Book Policy using the same parameters of the default OOTB policy.
New-AddressBookPolicy -Name "Contoso Address Book" -AddressLists "\Offline Global Address List", "\All Contacts", "\All Distribution Lists", "\All Rooms", "\All Users", "\All Groups", "\Public Folders" -OfflineAddressBook $oab -GlobalAddressList $gal -RoomList "\All Rooms"

Write-Host "Done...." -ForegroundColor Cyan

#Set a mailbox with the new policy
Write-Host "Assiging all Mailboxes to new Address Book policy" -ForegroundColor Green

get-Mailbox | Set-Mailbox -AddressBookPolicy "Contoso Address Book" 

Write-Host "Done...." -ForegroundColor Cyan


##############
##Config  IB##
###############

#Connect-MgGraph -Tenant ($t + '.onmicrosoft.com') -Scopes "User.Read","Application.ReadWrite.All"
#$appId="bcf62038-e005-436d-b970-2a472f8c1982" 
#$sp = Get-MgServicePrincipal -Filter "appid eq '$($appid)'"
#if ($sp -eq $null) { New-MgServicePrincipal -AppId $appId }
#Start-Process  "https://login.microsoftonline.com/common/adminconsent?client_id=$appId"

#Connect-MgGraph -Tenant ($t + '.onmicrosoft.com') -Scopes "User.Read","Application.ReadWrite.All"
#$appId="f46c682f-628c-48e6-b963-03309e34639e"
#$sp = Get-MgServicePrincipal -Filter "appid eq '$($appid)'"
#if ($sp -eq $null) {New-MgServicePrincipal -AppId $appId }
#Start-Process "https://login.microsoftonline.com/common/adminconsent?client_id=$appId"

#Enabling AuditLog for your Tenant
Write-Host "Enabling AuditLog for your Tenant" -ForegroundColor Green

Enable-OrganizationCustomization
Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true

Write-Host "Done..." -ForegroundColor Cyan

# Apply departments to users
$departments = @('HR', 'Sales', 'Research')

Write-Host "Applying Departments for all users" -ForegroundColor Green
$users = get-user | where { $_.SKUAssigned -eq $true }

for ($i = 0; $i -lt $users.Count; $i++) {
    $user = $users[$i]
    $department = $departments[$i % $departments.Count]

    # Example: Update user department in Active Directory
    Set-User -Identity $user -Department $department -Confirm:$false

    Write-Host "Updated $user with department $department"
}

Write-Host "Done..." -ForegroundColor Cyan


#Create Segments based on department
Write-Host "Creating IB Segments" -ForegroundColor Green

New-OrganizationSegment -Name "HR" -UserGroupFilter "Department -eq 'HR'"
New-OrganizationSegment -Name "Sales" -UserGroupFilter "Department -eq 'Sales'"
New-OrganizationSegment -Name "Research" -UserGroupFilter "Department -eq 'Research'"

Write-Host "Done..." -ForegroundColor Cyan



#Create InformationBarrier Policies
Write-Host "Creating IB Policies" -ForegroundColor Green

if ($policytype -eq 'Block') {
    #Blocks
    New-InformationBarrierPolicy -Name "Sales - Blocks - Research" -AssignedSegment "Sales" -SegmentsBlocked "Research" -State  "active"
    New-InformationBarrierPolicy -Name "Research - Blocks - Sales" -AssignedSegment "Research" -SegmentsBlocked "Sales" -State "active"
}


if ($policytype -eq 'Allow') {
    New-InformationBarrierPolicy -Name "HR - Allows - Research and Sales" -AssignedSegment "HR" -SegmentsAllowed "HR", "Research", "Sales" -State "active"
    New-InformationBarrierPolicy -Name "Sales - Allows - HR" -AssignedSegment "Sales" -SegmentsAllowed "Sales", "HR" -State "active"
    New-InformationBarrierPolicy -Name "Research Allows - HR" -AssignedSegment "Research" -SegmentsAllowed "Research", "HR" -State "active"
}


#Start Policy Application
Write-Host "Starting  Information Barrier Policies Application" -ForegroundColor Green
Start-InformationBarrierPoliciesApplication -Confirm:$false #IPPSSession Needed
Write-Host "The job has been created but will take about 1 hour to complete." -ForegroundColor Cyan

Write-Host "" -ForegroundColor Cyan

Write-Host "Gettinng Information Barrier Policies Application Status" -ForegroundColor Green
Get-InformationBarrierPoliciesApplicationStatus  #IPPSSession Needed
Write-Host "Done..." -ForegroundColor Cyan

#Enable IB for SharePoint
Write-Host "Enabling IB for SharePoint" -ForegroundColor Green


#To enable information barriers in SharePoint and OneDrive
Set-SPOTenant -InformationBarriersSuspension $false

#Enable Group Discoverability in SPO
Set-SPOTenant -ShowPeoplePickerGroupSuggestionsForIB $true

#needed for Teams Recordings
Set-SPOTenant -AppOnlyBypassPeoplePickerPolicies $true
Set-SPOTenant -AppBypassInformationBarriers $true

#enable for Teams (IBV1 Setting)
Set-SPOTenant -IBImplicitGroupBased $true

#optional

#Enable Org level Discoverability
#Set-PolicyConfig -InformationBarrierPeopleSearchRestriction 'Disabled'

#Disable Org Level Discoverability
#Set-PolicyConfig -InformationBarrierPeopleSearchRestriction 'Enabled'


Write-Host "Done..." -ForegroundColor Cyan


#udpate OneDrive sites:
Write-Host "Stamping exsiting Onedrive sites with Segments" -ForegroundColor Green
$updateODB = Start-SPOInformationBarriersPolicyComplianceReport -UpdateOneDriveSegments -Confirm:$false
Write-Host "Process started but will take about 1 hour to compelte" -ForegroundColor Cyan
Write-Host ""

Write-Host "Information Barriers has been configued but will take up to 24 hours to be fully functional!!" -ForegroundColor Green
Write-Host ""

Write-Host "Checking current state of Information Barriers" -ForegroundColor Cyan

#Get Segments:
Write-Host "Getting IB Segments" -ForegroundColor Green
Get-OrganizationSegment | fl  name, UserGroupFilter, ExoSegmentId #IPPSSession Needed

Write-Host ""

#Get  IB Policies
Write-Host "Getting IB Policies" -ForegroundColor Green
Get-InformationBarrierPolicy | FL  Name, AssignedSegment, SegmentsBlocked, SegmentsAllowed, ExoPolicyId, State, Guid , SegmentsAllowed, BlockVisibility, SegmentsBlocked, state #IPPSSession Needed

Write-Host ""

#Get Org Level Settings
Write-Host "Getting IB Org level settings" -ForegroundColor Green
Get-OrganizationConfig |  fl *IB*, *info* #ExchangeOnline Needed
Get-PolicyConfig |  fl *IB*, *info* #ExchangeOnline Needed

Write-Host ""

#Check SPO Settings
Write-Host "Getting IB settings in SPO" -ForegroundColor Green
Get-Spotenant | fl DefaultOneDriveInformationBarrierMode, InformationBarriersSuspension, IBImplicitGroupBased, ShowPeoplePickerGroupSuggestionsForIB, *bypass* #SPOService Needed

Write-Host ""

#check if users are compatible with each other:
Write-Host "Checking random user IB compatibility" -ForegroundColor Green
$users = get-user | where { $_.SKUAssigned -eq $true } | select UserPrincipalName
$randomUsers = $users | Get-Random

foreach ($randomUser in $randomUsers) {
    $randomUser2 = $users | Get-Random
    $results = Get-ExoInformationBarrierRelationship -RecipientId1 $randomUser.UserPrincipalName -RecipientId2 $randomUser2.UserPrincipalName
    $r1 = $results | select RecipientName1
    $r2 = $results | select RecipientName2
    $RecipientName1 = get-user $r1.RecipientName1 | select UserPrincipalName
    $RecipientName2 = get-user $r2.RecipientName2 | select UserPrincipalName
    $results 
    write-host "RecipientName1 is" $RecipientName1.UserPrincipalName
    write-host "RecipientName2 is" $RecipientName2.UserPrincipalName
    $randomUser = @()
    $randomUser2 = @() 
}

Write-Host ""

#get IB Settings per user
Write-Host "Getting IB per user" -ForegroundColor Green
$users = get-user | where { $_.SKUAssigned -eq $true }
foreach ($user in $users) { 
    Get-Recipient -Identity $user.UserPrincipalName | fl DisplayName, name, InformationBarrierSegments, WhenIBSegmentChanged, Department, AddressBookPolicy
}

Write-Host ""


#get IB Settings per ODB Site 
Write-Host "Getting IB Settings in OneDrive Sites" -ForegroundColor Green
$odburls = Get-SPOSite -IncludePersonalSite $true -Limit all -Filter "Url -like '-my.sharepoint.com/personal/'" | Select -ExpandProperty Url
foreach ($odburl in $odburls) { 
    get-sposite -Identity $odburl | FL Owner, URL, InformationSegment, InformationBarriersMode
}

Write-Host ""

#get IB Settings SPO Site
Write-Host "Getting IB Settings in OneDrive Sites" -ForegroundColor Green
$sposites = Get-SPOSite -IncludePersonalSite $false -Limit all | Select -ExpandProperty Url
foreach ($sposite in $sposites) { 
    get-sposite -Identity $sposite | FL Owner, URL, InformationSegment, InformationBarriersMode
}

Write-Host ""

Write-Host "Done........." -ForegroundColor Cyan
Write-Host "Information Barriers have been setup for $T, it could take 24 hours to take full effect." -ForegroundColor Green
