<#
.SYNOPSIS
This script connects to various Microsoft 365 services and retrieves information about Information Barriers (IB) settings and policies.

.DESCRIPTION
The script performs the following tasks:
1. Prompts the user for the tenant name.
2. Retrieves a list of users.
3. Connects to Exchange Online, Information Protection and Compliance (IPPSSession), and SharePoint Online (SPO) services.
4. Retrieves and displays the current state of Information Barriers, including segments, policies, and organization-level settings.
5. Checks SharePoint Online settings related to Information Barriers.
6. Checks the compatibility of random users with each other regarding Information Barriers.
7. Retrieves Information Barrier settings for each user.
8. Retrieves Information Barrier settings for OneDrive for Business (ODB) sites.
9. Retrieves Information Barrier settings for SharePoint Online sites.

.PARAMETER TenantName
The name of the tenant (e.g., M365x03708457).

.PARAMETER Users
A list of users retrieved from the tenant.

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

Requires the Exchange Online, Information Protection and Compliance, and SharePoint Online modules to be installed and imported.

.EXAMPLE
.\Check-IBConfig.ps1
Prompts for the tenant name and retrieves Information Barrier settings and policies for the specified tenant.
#>

#Tenant
$t = Read-Host "What is your tenant name, IE: M365x03708457"  

#Connect to Services
Connect-ExchangeOnline
Connect-SPOService -Url ('https://'+ $t + '-admin.sharepoint.com')

Write-Host "Checking current state of Information Barriers" -ForegroundColor Cyan

#get users parameter change be changed as needed
$users = get-user | where { $_.SKUAssigned -eq $true }

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
Write-Host "Getting IB Settings in SPO Sites" -ForegroundColor Green
$sposites = Get-SPOSite -IncludePersonalSite $false -Limit all | Select -ExpandProperty Url
foreach ($sposite in $sposites) { 
    get-sposite -Identity $sposite | FL Owner, URL, InformationSegment, InformationBarriersMode
}

Write-Host ""

Write-Host "Signing into IPPSSession for Segment and Policy Information" -ForegroundColor Green

Connect-IPPSSession -UseRPSSession:$false

#Get Segments:
Write-Host "Getting IB Segments" -ForegroundColor Green
Get-OrganizationSegment | fl  name, UserGroupFilter, ExoSegmentId #IPPSSession Needed

Write-Host ""

#Get  IB Policies
Write-Host "Getting IB Policies" -ForegroundColor Green
Get-InformationBarrierPolicy | FL  Name, AssignedSegment, SegmentsBlocked, SegmentsAllowed, ExoPolicyId, State, Guid , SegmentsAllowed, BlockVisibility, SegmentsBlocked, state #IPPSSession Needed


Write-Host "Done........." -ForegroundColor Cyan
