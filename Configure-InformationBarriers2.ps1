<#
.SYNOPSIS
This script configures Information Barriers (IB) and Address Book Policies in an Office 365 tenant.

.DESCRIPTION

The script performs the following tasks:

1. Prompts the user for the tenant name and the type of policies (Allow or Block).
2. Connects to various Office 365 services including Exchange Online, SharePoint Online, and IPPS.
3. Enables Organization Customizations
4. Creates an Address Book Policy to prevent an empty address book.
5. Assigns the new Address Book Policy to all mailboxes.
6. Applies department attributes to users.
7. Creates organization segments based on departments.
8. Creates Information Barrier Policies based on the selected policy type (Allow or Block).
9. Starts the application of Information Barrier Policies.
10. Enables Information Barriers for SharePoint and OneDrive.
11. Triggers Personal Site creations using "Request-SPOPersonalSite" for all users.
12. Updates existing OneDrive sites with segments.
13. Checks the current state of Information Barriers and retrieves various IB settings.
14. Checks IB compatibility between random users.
15. Retrieves IB settings for users, OneDrive sites, and SharePoint sites.

.PARAMETER TenantName
The name of the Office 365 tenant (e.g., M365x03708457).

.PARAMETER PolicyType
The type of policies to create: 'allow' or 'block'.

.NOTES
Authors: Mike Lee
Date: 1/30/2025
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


# Configure logging
function Log-Message {
    param (
        [string]$message,
        [string]$level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$level] $message"
    Add-Content -Path $logFile -Value $logEntry
    #Write-Host $message
}

function Get-TenantName {
    return Read-Host "What is your tenant name, IE: M365x03708457"
}

function Get-PolicyType {
    $validInput = $false
    while (-not $validInput) {
        Log-Message "Do you want Allow or Block Policies?"
        $policytype = Read-Host "Please enter 'allow' or 'block'"
        if ($policytype -eq "allow" -or $policytype -eq "block") {
            $validInput = $true
        }
        else {
            Log-Message "Invalid input. Please try again." "ERROR"
        }
    }
    return $policytype
}

function Connect-ToServices {
    try {
        Connect-ExchangeOnline
        Connect-IPPSSession -UseRPSSession:$false
        Connect-SPOService -Url ('https://' + $t + '-admin.sharepoint.com')
        Log-Message "Connected to Office 365 services."
    }
    catch {
        Log-Message "Error connecting to services: $_" "ERROR"
        Write-Host "Error connecting to services: $_"  -ForegroundColor red
    }
}

function Enable-OrgCustomization {
    Write-Host "Checking if Organization Customization is Enabled" -ForegroundColor Green
    Log-Message "Checking if Organization Customization is Enabled" 

    try {
        $IsDehydrated = Get-OrganizationConfig
        if ($IsDehydrated.IsDehydrated -eq $True) {
            Write-Host "Enabling Organization Customization" -ForegroundColor Green
            Log-Message "Enabling Organization Customization"
        
            Enable-OrganizationCustomization
        
            Write-Host "Done...." -ForegroundColor Cyan
            Log-Message "Done...."
        }

        if ($IsDehydrated.IsDehydrated -eq $False) { 
            Write-Host "Organization Customization Is Already Enabled" -ForegroundColor Yellow
            Log-Message "Organization Customization Is Already Enabled" -level INFO
        }
    }
    catch {
        Log-Message "Error enabling organization customization: $_" "ERROR"
        Write-Host "Error enabling organization customization: $_"  -ForegroundColor red
    }
}

Function Assign-AddressBookRole {

    try {
        Write-Host "Adding role 'Address Lists' to 'Organization Management' to allow for Address Book Management with the GA Account" -ForegroundColor Green
        Log-Message "Adding role 'Address Lists' to 'Organization Management' to allow for Address Book Management with the GA Account"

        New-ManagementRoleAssignment -SecurityGroup "Organization Management" -Role "Address Lists"

        Write-Host "Done...." -ForegroundColor Cyan
        Write-Host "After adding role 'Address Lists' to 'Organization Management', reconnecting to Exchange Online" -ForegroundColor Yellow

        Log-Message "Done...."
        Log-Message "After adding role 'Address Lists' to 'Organization Management', reconnecting to Exchange Online"

    }

    catch {
        Log-Message "Error Assigning Address Book Role: $_" "ERROR"
        Write-Host "Error Assigning Address Book Role $_"  -ForegroundColor red
    }

    Write-Host "Waiting 1 minute for the change to take effect." -ForegroundColor Green
    for ($i = 60; $i -ge 0; $i--) {
        Write-Host "$i seconds remaining"
        Start-Sleep -Seconds 1

    }
    Write-Host "Done...." -ForegroundColor Cyan
    Write-Host "Signing back into Exchange Online to reflect new roles" -ForegroundColor Green
    Connect-ExchangeOnline

}

function Create-AddressBookPolicy {
    try {
        Write-Host "Creating Address Book Policy" -ForegroundColor Green
        Log-Message "Creating Address Book Policy"
        #use the current OAB
        $oab = Get-OfflineAddressBook 'Default Offline Address Book'
    
        #use the current GAL
        $gal = Get-GlobalAddressList 'Default Global Address List'
    
        #Creating the Policy
        New-AddressBookPolicy -Name "Contoso Address Book" -AddressLists "\Offline Global Address List", "\All Contacts", "\All Distribution Lists", "\All Rooms", "\All Users", "\All Groups", "\Public Folders" -OfflineAddressBook $oab -GlobalAddressList $gal -RoomList "\All Rooms"
        Write-Host "Done...." -ForegroundColor Cyan
        Log-Message "Done...."
    }
    catch {
        Log-Message "Error creating Address Book Policy: $_" "ERROR"
        Write-Host "Error creating Address Book Policy: $_"  -ForegroundColor red
    }

}

function Assign-AddressBookPolicy {
    try {
        Write-Host "Assiging all Mailboxes to new Address Book policy" -ForegroundColor Green
        Log-Message "Assigning all Mailboxes to new Address Book policy"
        Get-Mailbox | Set-Mailbox -AddressBookPolicy "Contoso Address Book"
        Write-Host "Done...." -ForegroundColor Cyan
        Log-Message "Done...."
    }
    catch {
        Log-Message "Error assigning Address Book Policy: $_" "ERROR"
        Write-Host "Error assigning Address Book Policy: $_"  -ForegroundColor red
    }
}

function Apply-DepartmentsToUsers {
    try {
        $global:departmentsArray = (Read-Host "Enter department names separated by commas (e.g., HR, Sales, Research)").Split(',').Trim()
        Write-Host "Applying Departments for all users" -ForegroundColor Green
        Log-Message "Applying Departments for all users"
        $users = Get-User | Where-Object { $_.SKUAssigned -eq $true }
        for ($i = 0; $i -lt $users.Count; $i++) {
            $user = $users[$i]
            $department = $departmentsArray[$i % $departmentsArray.Count]
        
            #Update user department in Active Directory
            Set-User -Identity $user.UserPrincipalName -Department $department -Confirm:$false
        
            Write-Host "Updated $($user.UserPrincipalName) with department $department" -ForegroundColor Green
            Log-Message "Updated $($user.UserPrincipalName) with department $department"
        }
        Write-Host "Done..." -ForegroundColor Cyan
        Log-Message "Done..."
    }
    catch {
        Log-Message "Error applying departments: $_" "ERROR"
        Write-Host "Error applying departments: $_"  -ForegroundColor red
    }
}

function Provision-OneDriveSites {
    try {
        $users = Get-User | Where-Object { $_.SKUAssigned -eq $true }
    
        Write-Host "Provisioning OneDrive Sites" -ForegroundColor Green
        Log-Message "Provisioning OneDrive Sites"
    
        foreach ($user in $users) {
            Write-Host "Provisioning OneDrive Sites for $($user.UserPrincipalName)" -ForegroundColor Cyan
            Log-Message "Provisioning OneDrive Sites for $($user.UserPrincipalName)"
            Request-SPOPersonalSite -UserEmails $user.UserPrincipalName
            Write-Host "Done..." -ForegroundColor Cyan
            Log-Message "Done..."
        }
    }
    catch {
        Log-Message "Error provisioning OneDrive Sites: $_" "ERROR"
        Write-Host "Error provisioning OneDrive Sites: $_"  -ForegroundColor red
    }
}

function Create-Segments {
    try {
        Write-Host "Creating IB Segments" -ForegroundColor Green
        Log-Message "Creating IB Segments"
        foreach ($department in  $global:departmentsArray) {
            New-OrganizationSegment -Name "$department" -UserGroupFilter "Department -eq '$department'"
            Write-Host "Created segment for department: $department" -ForegroundColor Green
            Log-Message "Created segment for department: $department"
        }
        Log-Message "Done..."
        Write-Host "Done..." -ForegroundColor Cyan
    }
    catch {
        Log-Message "Error creating IB Segments: $_" "ERROR"
        Write-Host "Error creating IB Segments: $_" -ForegroundColor red
    }
}

function Create-IBPolicies {
    try {
        Write-Host "Creating IB Policies" -ForegroundColor Green
        Log-Message "Creating IB Policies"
    
        if ($policytype -eq 'Block') {
            $Blockdepartments = (Read-Host "Which Departments Block each other from '$global:departmentsArray' (e.g.Banking, Research)").Split(',').Trim()

            foreach ($dept1 in  $Blockdepartments) {
                foreach ($dept2 in $Blockdepartments) {
                    if ($dept1 -ne $dept2) {
                        New-InformationBarrierPolicy -Name "$dept1 - Blocks - $dept2" -AssignedSegment "$dept1" -SegmentsBlocked "$dept2" -State  "active"
                        Write-Host "$dept1 blocks $dept2 policy created."
                        Log-Message "$dept1 blocks $dept2 policy created."
                    }
                }
            }
        }
        if ($policytype -eq 'Allow') {
            $Allowdepartments = (Read-Host "Which Departments Allow each other from '$global:departmentsArray'(e.g.Corp, Research)").Split(',').Trim()
     
            foreach ($dept1 in  $Allowdepartments) {
                foreach ($dept2 in $Allowdepartments) {
                    if ($dept1 -ne $dept2) {
                        New-InformationBarrierPolicy -Name "$dept1 - Allows - $dept2" -AssignedSegment "$dept1" -SegmentsAllowed "$dept1, $dept2" -State  "active"
                        Write-Host "$dept1 Allows $dept2 policy created."
                        Log-Message "$dept1 Allows $dept2 policy created."
                    }
                }
            }
        }
    } catch {
        Log-Message "Error creating IB Policies: $_" "ERROR"
        Write-Host "Error creating IB Policies: $_" -ForegroundColor Red
    }
}
        function Start-PolicyApplication {
            try {
                Write-Host "Starting  Information Barrier Policies Application" -ForegroundColor Green
                Log-Message "Starting Information Barrier Policies Application"
    
                Start-InformationBarrierPoliciesApplication -Confirm:$false
    
                Write-Host "The job has been created but will take about 1 hour to complete." -ForegroundColor Cyan
                Log-Message "The job has been created but will take about 1 hour to complete."
            }
            catch {
                Log-Message "Error starting Information Barrier Policies Application: $_" "ERROR"
                Write-Host "Error starting Information Barrier Policies Application: $_" -ForegroundColor Red
            }
        }

        function Get-PolicyApplicationStatus {
            try {
                Write-Host "Gettinng Information Barrier Policies Application Status" -ForegroundColor Green
                Log-Message "Getting Information Barrier Policies Application Status"
    
                Get-InformationBarrierPoliciesApplicationStatus
    
                Write-Host "Done..." -ForegroundColor Cyan
                Log-Message "Done..."
            }
            catch {
                Log-Message "Error getting Information Barrier Policies Application Status: $_" "ERROR"
                Write-Host "Error getting Information Barrier Policies Application Status: $_" -ForegroundColor Red
            }
        }

        function Enable-IBForSharePoint {
            try {
                Write-Host "Enabling IB for SharePoint" -ForegroundColor Green
                Log-Message "Enabling IB for SharePoint"
                #To enable information barriers in SharePoint and OneDrive
                Set-SPOTenant -InformationBarriersSuspension $false
    
                #Enable Group Discoverability in SPO
                Set-SPOTenant -ShowPeoplePickerGroupSuggestionsForIB $true
     
                #needed for Teams Recordings
                Set-SPOTenant -AppOnlyBypassPeoplePickerPolicies $true
                Set-SPOTenant -AppBypassInformationBarriers $true
    
                #enable for Teams (IBV1 Setting)
                Set-SPOTenant -IBImplicitGroupBased $true
    
                Write-Host "Done..." -ForegroundColor Cyan
                Log-Message "Done..."
            }
            catch {
                Log-Message "Error enabling IB for SharePoint: $_" "ERROR"
                Write-Host "Error enabling IB for SharePoint: $_" -ForegroundColor Red
            }
        }

        function Update-OneDriveSites {
            try {
                Write-Host "Stamping exsiting Onedrive sites with Segments" -ForegroundColor Green
                Log-Message "Stamping existing OneDrive sites with Segments"
    
                $updateODB = Start-SPOInformationBarriersPolicyComplianceReport -UpdateOneDriveSegments -Confirm:$false
    
                Write-Host "Process started but will take about 1 hour to compelte" -ForegroundColor Cyan
                Log-Message "Process started but will take about 1 hour to complete"
                Write-Host ""
            }
            catch {
                Log-Message "Error stamping existing OneDrive sites with Segments: $_" "ERROR"
                Write-Host "Error stamping existing OneDrive sites with Segments:: $_" -ForegroundColor Red
            }
        }

        function Get-IBSegments {
            try {
                Write-Host "Getting IB Segments" -ForegroundColor Green
                Log-Message "Getting IB Segments"
    
                Get-OrganizationSegment | Format-List Name, UserGroupFilter, ExoSegmentId
                Write-Host "Done..." -ForegroundColor Green
                Log-Message "Done..."
            }
            catch {
                Log-Message "Error getting IB Segments: $_" "ERROR"
                Write-Host "Error getting IB Segments: $_" -ForegroundColor Red
            }
        }

        function Get-IBPolicies {
            try {
                Write-Host "Getting IB Policies" -ForegroundColor Green
                Log-Message "Getting IB Policies"
                Get-InformationBarrierPolicy | Format-List Name, AssignedSegment, SegmentsBlocked, SegmentsAllowed, ExoPolicyId, State, Guid, SegmentsAllowed, BlockVisibility, SegmentsBlocked, State
                Write-Host "Done..." -ForegroundColor Green
                Log-Message "Done..."
            }
            catch {
                Log-Message "Error getting IB Policies: $_" "ERROR"
                Write-Host "Error getting IB Policies: $_" -ForegroundColor Red
            }
        }

        function Get-OrgLevelSettings {
            try {
                Write-Host "Getting IB Org level settings" -ForegroundColor Green
                Log-Message "Getting IB Org level settings"
    
                Get-OrganizationConfig | Format-List *IB*, *info*
                Get-PolicyConfig | Format-List *IB*, *info*
    
                Write-Host "Done..." -ForegroundColor Green
                Log-Message "Done..."
            }
            catch {
                Log-Message "Error getting IB Org level settings: $_" "ERROR"
                Write-Host "Error getting IB Org level settings: $_" -ForegroundColor Red
            }
        }

        function Get-SPOIBSettings {
            try {
                Write-Host "Getting IB settings in SPO" -ForegroundColor Green
                Log-Message "Getting IB settings in SPO"
    
                Get-SPOTenant | Format-List DefaultOneDriveInformationBarrierMode, InformationBarriersSuspension, IBImplicitGroupBased, ShowPeoplePickerGroupSuggestionsForIB, *bypass*
                Write-Host "Done..." -ForegroundColor Green
                Log-Message "Done..."
            }
            catch {
                Log-Message "Error getting IB settings in SPO: $_" "ERROR"
                Write-Host "Error getting IB settings in SPO: $_" -ForegroundColor Red
            }
        }

        function Check-UserCompatibility {
            try {
                Write-Host "Checking random user IB compatibility" -ForegroundColor Green
                Log-Message "Checking random user IB compatibility"
                $users = Get-User | Where-Object { $_.SKUAssigned -eq $true }
                $randomUsers = $users | Get-Random
    
                foreach ($randomUser in $randomUsers) {
                    $randomUser2 = $users | Get-Random
                    $results = Get-ExoInformationBarrierRelationship -RecipientId1 $randomUser.UserPrincipalName -RecipientId2 $randomUser2.UserPrincipalName
                    $r1 = $results | Select-Object -ExpandProperty RecipientName1
                    $r2 = $results | Select-Object -ExpandProperty RecipientName2
                    $RecipientName1 = Get-User $r1 | Select-Object -ExpandProperty UserPrincipalName
                    $RecipientName2 = Get-User $r2 | Select-Object -ExpandProperty UserPrincipalName
                    $results
                    write-host "RecipientName1 is" $RecipientName1.UserPrincipalName
                    write-host "RecipientName2 is" $RecipientName2.UserPrincipalName
                    Log-Message "RecipientName1 is $RecipientName1"
                    Log-Message "RecipientName2 is $RecipientName2"
                    $randomUser = @()
                    $randomUser2 = @()
                }
                Log-Message "Done..."
                Write-Host "Done..." -ForegroundColor Green
            }
            catch {
                Log-Message "Error checking random user IB compatibility: $_" "ERROR"
                Write-Host "Error checking random user IB compatibility: $_" -ForegroundColor Red
            }
        }

        function Get-IBPerUser {
            try {
                Write-Host "Getting IB per user" -ForegroundColor Green
                Log-Message "Getting IB per user"
    
                $users = Get-User | Where-Object { $_.SKUAssigned -eq $true }
                foreach ($user in $users) {
                    Get-Recipient -Identity $user.UserPrincipalName | Format-List DisplayName, Name, InformationBarrierSegments, WhenIBSegmentChanged, Department, AddressBookPolicy
                }
                Log-Message "Done..."
                Write-Host "Done..." -ForegroundColor Green
            }
            catch {
                Log-Message "Error getting IB per user: $_" "ERROR"
                Write-Host "Error getting IB per user:  $_" -ForegroundColor Red
            }
        }

        function Get-IBSettingsInOneDriveSites {
            try {
                Write-Host "Getting IB Settings in OneDrive Sites" -ForegroundColor Green
                Log-Message "Getting IB Settings in OneDrive Sites"
    
                $odburls = Get-SPOSite -IncludePersonalSite $true -Limit all -Filter "Url -like '-my.sharepoint.com/personal/'" | Select-Object -ExpandProperty Url
    
                foreach ($odburl in $odburls) {
                    Get-SPOSite -Identity $odburl | Format-List Owner, URL, InformationSegment, InformationBarriersMode
                }
                Log-Message "Done..."
                Write-Host "Done..." -ForegroundColor Green
            }
            catch {
                Log-Message "Error getting IB Settings in OneDrive Sites: $_" "ERROR"
                Write-Host "Error getting IB Settings in OneDrive Sites:  $_" -ForegroundColor Red
            }
        }

        function Get-IBSettingsInSharePointSites {
            try {
                Write-Host "Getting IB Settings in SPO Sites" -ForegroundColor Green
                Log-Message "Getting IB Settings in SharePoint Sites"
    
                $sposites = Get-SPOSite -IncludePersonalSite $false -Limit all | Select-Object -ExpandProperty Url
                foreach ($sposite in $sposites) {
                    Get-SPOSite -Identity $sposite | Format-List Owner, URL, InformationSegment, InformationBarriersMode
                }
                Log-Message "Done..."
                Write-Host "Done..." -ForegroundColor Green
            }
            catch {
                Log-Message "Error getting IB Settings in SharePoint Sites: $_" "ERROR"
                Write-Host "Error getting IB Settings in SharePoint Sites:  $_" -ForegroundColor Red
            }
        }

        # Main script execution
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $logFile = "$env:TEMP\SharePointScriptLog_$timestamp.txt"
        $t = Get-TenantName
        $policytype = Get-PolicyType

        Connect-ToServices
        Enable-OrgCustomization
        Assign-AddressBookRole
        Create-AddressBookPolicy
        Assign-AddressBookPolicy
        Apply-DepartmentsToUsers
        Provision-OneDriveSites
        Create-Segments
        Create-IBPolicies
        Start-PolicyApplication
        Get-PolicyApplicationStatus
        Enable-IBForSharePoint
        Update-OneDriveSites

        Get-IBSegments
        Get-IBPolicies
        Get-OrgLevelSettings
        Get-SPOIBSettings
        Check-UserCompatibility
        Get-IBPerUser
        Get-IBSettingsInOneDriveSites
        Get-IBSettingsInSharePointSites

        Log-Message "Information Barriers have been setup for $t, it could take 24 hours to take full effect."
        Write-Host "Information Barriers have been setup for $T, it could take 24 hours to take full effect." -ForegroundColor Green
