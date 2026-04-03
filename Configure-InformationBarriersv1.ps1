<#
.SYNOPSIS
This script configures Information Barriers (IB) in an Office 365 tenant.

.DESCRIPTION

The script performs the following tasks:

1. Validates prerequisites (modules, permissions, connectivity).
2. Connects to various Office 365 services including Exchange Online, SharePoint Online, and IPPS.
3. Applies department attributes to users.
4. Creates organization segments based on departments.
5. Creates Information Barrier Policies based on the selected policy type (Allow or Block).
6. Starts the application of Information Barrier Policies.
7. Enables Information Barriers for SharePoint and OneDrive.
8. Triggers Personal Site creations using "Request-SPOPersonalSite" for all users.
9. Updates existing OneDrive sites with segments.
10. Checks the current state of Information Barriers and retrieves various IB settings.
11. Checks IB compatibility between random users.
12. Retrieves IB settings for users, OneDrive sites, and SharePoint sites.

.PARAMETER TenantName
The name of the Office 365 tenant (e.g., M365x03708457). If not provided, you will be prompted.

.PARAMETER PolicyType
The type of policies to create: 'Allow' or 'Block'.

.PARAMETER Departments
Array of department names to create segments for. Defaults to @('HR', 'Sales', 'Research').

.PARAMETER NeutralDepartment
The name of the neutral department that can communicate with all departments. 
For Block policies: This department will NOT be blocked by others.
For Allow policies: This department can communicate with specified departments.
Defaults to 'HR'.

.PARAMETER BlockedDepartmentPairs
(Block policies only) Array of departments that will block each other bi-directionally.
If not specified, defaults to all non-neutral departments.
Example: @('Sales', 'Research') - Sales and Research will block each other, but not HR.

.PARAMETER AllowedWithNeutralDepartments
(Allow policies only) Array of departments that can communicate with the neutral department.
If not specified, defaults to all non-neutral departments.
Example: @('Sales', 'Research') - Sales and Research can communicate with HR, but not with each other.

.PARAMETER LogPath
Path to the log file. Defaults to script directory with timestamp.

.PARAMETER SkipPrerequisiteCheck
Skip the prerequisite validation check.

.NOTES
Authors: Mike Lee
Date: 9/18/2024
Updated: 4/2/2026 - removed addresbook population and user segment assignment to focus on core IB configuration and policy creation.
Version: 2.0
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
- Ensure that the necessary modules (e.g., ExchangeOnlineManagement, Microsoft.Online.SharePoint.PowerShell) are installed.

.EXAMPLE
.\Configure-InformationBarriers.ps1 -TenantName "M365x03708457" -PolicyType "Block"
Configures Information Barriers with Block policies. HR (neutral) can communicate with all, while Sales and Research block each other.

.EXAMPLE
.\Configure-InformationBarriers.ps1 -TenantName "contoso" -PolicyType "Allow" -NeutralDepartment "HR"
Configures Allow policies where HR can communicate with Sales and Research, but Sales and Research cannot communicate with each other.

.EXAMPLE
.\Configure-InformationBarriers.ps1 -PolicyType "Block" -Departments @('HR', 'Sales', 'Research', 'Legal') -NeutralDepartment "HR" -BlockedDepartmentPairs @('Sales', 'Research', 'Legal')
Creates segments for 4 departments where HR is neutral, and Sales, Research, and Legal all block each other.

.EXAMPLE
.\Configure-InformationBarriers.ps1 -PolicyType "Allow" -NeutralDepartment "Management" -AllowedWithNeutralDepartments @('Finance', 'IT')
Management department can communicate with Finance and IT, but Finance and IT cannot communicate with each other.

.EXAMPLE
.\Configure-InformationBarriers.ps1 -Verbose
Runs the script with verbose output for detailed logging.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Enter the tenant name (e.g., M365x03708457)")]
    [string]$TenantName,

    [Parameter(Mandatory = $false, HelpMessage = "Select policy type: Allow or Block")]
    [ValidateSet('Allow', 'Block', IgnoreCase = $true)]
    [string]$PolicyType = 'Block',

    [Parameter(Mandatory = $false, HelpMessage = "Array of department names to create segments for")]
    [ValidateNotNullOrEmpty()]
    [string[]]$Departments = @('HR', 'Sales', 'Research'),

    [Parameter(Mandatory = $false, HelpMessage = "Name of the neutral department that can communicate with all departments")]
    [ValidateNotNullOrEmpty()]
    [string]$NeutralDepartment = 'HR',

    [Parameter(Mandatory = $false, HelpMessage = "For Block policies: Departments that block each other (e.g., @('Sales', 'Research'))")]
    [string[]]$BlockedDepartmentPairs = @('Sales', 'Research'),

    [Parameter(Mandatory = $false, HelpMessage = "For Allow policies: Departments that can communicate with the neutral department")]
    [string[]]$AllowedWithNeutralDepartments = @('Sales', 'Research'),

    [Parameter(Mandatory = $false)]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPrerequisiteCheck
)

#region Script Variables
$script:ErrorLog = @()
$script:WarningLog = @()
$script:UserCache = $null
$script:ScriptStartTime = Get-Date

# Set log path if not provided
if (-not $LogPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $LogPath = Join-Path $env:TEMP ('IB-Configuration-Log-' + $timestamp + '.log')
}
#endregion

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
    Writes messages to console and log file with timestamps.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Verbose', 'Debug')]
        [string]$Level = 'Info',
        
        [Parameter(Mandatory = $false)]
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    try {
        Add-Content -Path $LogPath -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write to log file: $_"
    }
    
    # Write to console unless suppressed
    if (-not $NoConsole) {
        switch ($Level) {
            'Error' { Write-Host $Message -ForegroundColor Red }
            'Warning' { Write-Host $Message -ForegroundColor Yellow }
            'Success' { Write-Host $Message -ForegroundColor Green }
            'Verbose' { Write-Verbose $Message }
            'Debug' { Write-Debug $Message }
            default { Write-Host $Message -ForegroundColor Cyan }
        }
    }
    
    # Track errors and warnings
    if ($Level -eq 'Error') {
        $script:ErrorLog += @{
            Timestamp = $timestamp
            Message   = $Message
        }
    }
    elseif ($Level -eq 'Warning') {
        $script:WarningLog += @{
            Timestamp = $timestamp
            Message   = $Message
        }
    }
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
    Validates that required modules are installed and available.
    #>
    [CmdletBinding()]
    param()
    
    Write-Log "Checking prerequisites..." -Level Info
    
    $requiredModules = @(
        @{Name = 'ExchangeOnlineManagement'; MinVersion = '2.0.0' }
        @{Name = 'Microsoft.Online.SharePoint.PowerShell'; MinVersion = '16.0.0' }
    )
    
    $missingModules = @()
    $outdatedModules = @()
    $installFailures = @()
    
    foreach ($module in $requiredModules) {
        $installedModule = Get-Module -Name $module.Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        
        if (-not $installedModule) {
            $missingModules += $module
            Write-Log "Module '$($module.Name)' is not installed." -Level Warning
        }
        elseif ($installedModule.Version -lt [version]$module.MinVersion) {
            $outdatedModules += "$($module.Name) (Installed: $($installedModule.Version), Required: $($module.MinVersion))"
            Write-Log "Module '$($module.Name)' version $($installedModule.Version) is outdated. Minimum required: $($module.MinVersion)" -Level Warning
        }
        else {
            Write-Log "Module '$($module.Name)' version $($installedModule.Version) is installed." -Level Success
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Log "Attempting to install $($missingModules.Count) missing module(s)..." -Level Info
        
        foreach ($module in $missingModules) {
            Write-Log "Installing module '$($module.Name)' (minimum version $($module.MinVersion))..." -Level Info
            try {
                Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
                $installed = Get-Module -Name $module.Name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
                Write-Log "Successfully installed '$($module.Name)' version $($installed.Version)." -Level Success
            }
            catch {
                $installFailures += $module.Name
                Write-Log "Failed to install '$($module.Name)': $($_.Exception.Message)" -Level Error
            }
        }
        
        if ($installFailures.Count -gt 0) {
            Write-Log "Could not install the following modules: $($installFailures -join ', ')" -Level Error
            Write-Log "Install them manually using: Install-Module -Name <ModuleName> -Scope CurrentUser" -Level Info
            throw "Prerequisites check failed. Could not install required modules: $($installFailures -join ', ')"
        }
    }
    
    if ($outdatedModules.Count -gt 0) {
        Write-Log "Outdated modules detected: $($outdatedModules -join ', ')" -Level Warning
        Write-Log "Consider updating with: Update-Module -Name <ModuleName>" -Level Info
    }
    
    Write-Log "Prerequisites check completed successfully." -Level Success
    return $true
}

function Connect-Services {
    <#
    .SYNOPSIS
    Connects to required Office 365 services.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantName
    )
    
    Write-Log "Connecting to Office 365 services..." -Level Info
    
    try {
        # Connect to Exchange Online
        Write-Log "Connecting to Exchange Online..." -Level Info
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        Write-Log "Successfully connected to Exchange Online." -Level Success
        
        # Connect to IPPS Session
        Write-Log "Connecting to Security & Compliance Center..." -Level Info
        Connect-IPPSSession -ShowBanner:$false -ErrorAction Stop
        Write-Log "Successfully connected to Security & Compliance Center." -Level Success
        
        # Import SharePoint Online module
        Write-Log "Loading SharePoint Online module..." -Level Info
        if ($PSVersionTable.PSVersion.Major -gt 5) {
            Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -DisableNameChecking -ErrorAction Stop
        }
        else {
            Import-Module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking -ErrorAction Stop
        }
        
        # Connect to SharePoint Online
        $spoAdminUrl = "https://$TenantName-admin.sharepoint.com"
        Write-Log "Connecting to SharePoint Online: $spoAdminUrl" -Level Info
        Connect-SPOService -Url $spoAdminUrl -ErrorAction Stop
        Write-Log "Successfully connected to SharePoint Online." -Level Success
        
        return $true
    }
    catch {
        Write-Log "Failed to connect to services: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-CachedUsers {
    <#
    .SYNOPSIS
    Retrieves and caches licensed users to avoid repeated queries.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    if ($script:UserCache -and -not $Force) {
        Write-Log "Using cached user list ($($script:UserCache.Count) users)." -Level Verbose
        return $script:UserCache
    }
    
    Write-Log "Retrieving licensed users from tenant..." -Level Info
    try {
        # Use Get-Mailbox which is compatible with both Exchange Online and IPPS sessions
        # Filter for UserMailbox type to exclude shared/resource mailboxes
        $script:UserCache = Get-Mailbox -ResultSize Unlimited -ErrorAction Stop | 
        Where-Object { $_.RecipientTypeDetails -eq 'UserMailbox' }
        
        Write-Log "Retrieved $($script:UserCache.Count) user mailboxes." -Level Success
        return $script:UserCache
    }
    catch {
        Write-Log "Failed to retrieve users: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
    Executes a script block with retry logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$DelaySeconds = 5,
        
        [Parameter(Mandatory = $false)]
        [string]$OperationName = "Operation"
    )
    
    $attempt = 0
    $success = $false
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        try {
            Write-Log "Attempting $OperationName (Attempt $attempt of $MaxRetries)..." -Level Verbose
            & $ScriptBlock
            $success = $true
            Write-Log "$OperationName completed successfully." -Level Verbose
        }
        catch {
            if ($attempt -lt $MaxRetries) {
                Write-Log "$OperationName failed (Attempt $attempt): $($_.Exception.Message). Retrying in $DelaySeconds seconds..." -Level Warning
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                Write-Log "$OperationName failed after $MaxRetries attempts: $($_.Exception.Message)" -Level Error
                throw
            }
        }
    }
}

function Write-ProgressBar {
    <#
    .SYNOPSIS
    Displays a progress bar with countdown.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Seconds,
        
        [Parameter(Mandatory = $false)]
        [string]$Activity = "Waiting"
    )
    
    for ($i = $Seconds; $i -ge 0; $i--) {
        $percentComplete = (($Seconds - $i) / $Seconds) * 100
        Write-Progress -Activity $Activity -Status "$i seconds remaining" -PercentComplete $percentComplete
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $Activity -Completed
}

#region Main Script Logic

try {
    Write-Log "======================================" -Level Info
    Write-Log "Information Barriers Configuration Script" -Level Info
    Write-Log "Started: $($script:ScriptStartTime)" -Level Info
    Write-Log "Log File: $LogPath" -Level Info
    Write-Log "======================================" -Level Info
    
    # Prompt for parameters if not provided
    if (-not $TenantName) {
        $TenantName = Read-Host "Enter your tenant name (e.g., M365x03708457)"
        if ([string]::IsNullOrWhiteSpace($TenantName)) {
            throw "Tenant name is required."
        }
    }
    
    if (-not $PolicyType) {
        do {
            $PolicyType = Read-Host "Enter policy type (Allow or Block)"
        } while ($PolicyType -notmatch '^(Allow|Block)$')
    }
    
    # Normalize policy type to proper case
    $PolicyType = (Get-Culture).TextInfo.ToTitleCase($PolicyType.ToLower())
    
    # Validate and set defaults for policy configuration
    if ($PolicyType -eq 'Block') {
        # For Block policies: Set default blocked department pairs if not provided
        if (-not $BlockedDepartmentPairs) {
            # Default: All non-neutral departments block each other
            $BlockedDepartmentPairs = $Departments | Where-Object { $_ -ne $NeutralDepartment }
            Write-Log "Block policies will be created between: $($BlockedDepartmentPairs -join ' <-> ')" -Level Info
        }
        
        # Validate that neutral department exists in Departments
        if ($Departments -notcontains $NeutralDepartment) {
            throw "Neutral department '$NeutralDepartment' must be included in the Departments array."
        }
        
        # Validate blocked departments exist in Departments
        foreach ($dept in $BlockedDepartmentPairs) {
            if ($Departments -notcontains $dept) {
                throw "Blocked department '$dept' is not in the Departments array."
            }
        }
    }
    elseif ($PolicyType -eq 'Allow') {
        # For Allow policies: Set default allowed departments if not provided
        if (-not $AllowedWithNeutralDepartments) {
            # Default: All non-neutral departments can communicate with neutral
            $AllowedWithNeutralDepartments = $Departments | Where-Object { $_ -ne $NeutralDepartment }
            Write-Log "Allow policies will enable communication between '$NeutralDepartment' and: $($AllowedWithNeutralDepartments -join ', ')" -Level Info
        }
        
        # Validate that neutral department exists in Departments
        if ($Departments -notcontains $NeutralDepartment) {
            throw "Neutral department '$NeutralDepartment' must be included in the Departments array."
        }
        
        # Validate allowed departments exist in Departments
        foreach ($dept in $AllowedWithNeutralDepartments) {
            if ($Departments -notcontains $dept) {
                throw "Allowed department '$dept' is not in the Departments array."
            }
        }
    }
    
    Write-Log "Configuration Parameters:" -Level Info
    Write-Log "  Tenant Name: $TenantName" -Level Info
    Write-Log "  Policy Type: $PolicyType" -Level Info
    Write-Log "  Departments: $($Departments -join ', ')" -Level Info
    Write-Log "  Neutral Department: $NeutralDepartment" -Level Info
    if ($PolicyType -eq 'Block') {
        Write-Log "  Departments that block each other: $($BlockedDepartmentPairs -join ', ')" -Level Info
    }
    else {
        Write-Log "  Departments allowed with neutral: $($AllowedWithNeutralDepartments -join ', ')" -Level Info
    }
    
    # Check prerequisites
    if (-not $SkipPrerequisiteCheck) {
        Test-Prerequisites
    }
    else {
        Write-Log "Skipping prerequisite check as requested." -Level Warning
    }
    
    # Connect to services
    Connect-Services -TenantName $TenantName


    #region Apply Departments to Users
    Write-Log "Applying department attributes to users..." -Level Info
    
    try {
        $users = Get-CachedUsers
        $userCount = $users.Count
        Write-Log "Found $userCount user mailboxes." -Level Info
        
        $counter = 0
        foreach ($user in $users) {
            $counter++
            $department = $Departments[($counter - 1) % $Departments.Count]
            $percentComplete = ($counter / $userCount) * 100
            Write-Progress -Activity "Applying Departments" -Status "Processing $counter of $userCount - Assigning to $department" -PercentComplete $percentComplete
            
            try {
                Set-User -Identity $user.UserPrincipalName -Department $department -Confirm:$false -ErrorAction Stop
                Write-Log "Assigned $($user.UserPrincipalName) to department: $department" -Level Verbose
            }
            catch {
                Write-Log "Failed to assign department to $($user.UserPrincipalName): $($_.Exception.Message)" -Level Warning
            }
        }
        Write-Progress -Activity "Applying Departments" -Completed
        Write-Log "Department assignment completed." -Level Success
    }
    catch {
        Write-Log "Failed to apply departments: $($_.Exception.Message)" -Level Error
        throw
    }
    #endregion
    
    #region Provision OneDrive Sites
    Write-Log "Provisioning OneDrive sites for all users..." -Level Info
    
    try {
        $users = Get-CachedUsers
        $userCount = $users.Count
        Write-Log "Provisioning OneDrive for $userCount users..." -Level Info
        
        # Batch users for efficiency (SPO can handle multiple at once)
        $batchSize = 200
        $batches = [Math]::Ceiling($userCount / $batchSize)
        
        for ($i = 0; $i -lt $batches; $i++) {
            $startIndex = $i * $batchSize
            $endIndex = [Math]::Min(($i + 1) * $batchSize, $userCount) - 1
            $batchUsers = $users[$startIndex..$endIndex]
            $userEmails = $batchUsers | ForEach-Object { $_.UserPrincipalName }
            
            $percentComplete = (($i + 1) / $batches) * 100
            Write-Progress -Activity "Provisioning OneDrive Sites" -Status "Processing batch $($i + 1) of $batches" -PercentComplete $percentComplete
            
            try {
                Request-SPOPersonalSite -UserEmails $userEmails -ErrorAction Stop
                Write-Log "Provisioned OneDrive for batch $($i + 1) ($($batchUsers.Count) users)" -Level Verbose
            }
            catch {
                Write-Log "Failed to provision OneDrive for batch $($i + 1): $($_.Exception.Message)" -Level Warning
            }
        }
        Write-Progress -Activity "Provisioning OneDrive Sites" -Completed
        Write-Log "OneDrive provisioning requests completed." -Level Success
    }
    catch {
        Write-Log "Failed to provision OneDrive sites: $($_.Exception.Message)" -Level Error
        throw
    }
    #endregion

    #region Create Organization Segments
    Write-Log "Creating organization segments based on departments..." -Level Info
    
    try {
        foreach ($department in $Departments) {
            # Check if segment already exists
            $existingSegment = Get-OrganizationSegment -Identity $department -ErrorAction SilentlyContinue
            
            if ($existingSegment) {
                Write-Log "Segment '$department' already exists." -Level Warning
            }
            else {
                Write-Log "Creating segment for department: $department" -Level Info
                New-OrganizationSegment -Name $department -UserGroupFilter "Department -eq '$department'" -ErrorAction Stop
                Write-Log "Successfully created segment: $department" -Level Success
            }
        }
        Write-Log "Organization segment creation completed." -Level Success
    }
    catch {
        Write-Log "Failed to create organization segments: $($_.Exception.Message)" -Level Error
        throw
    }
    #endregion
    
    #region Create Information Barrier Policies
    Write-Log "Creating Information Barrier Policies (Type: $PolicyType)..." -Level Info
    
    try {
        if ($PolicyType -eq 'Block') {
            # Block policies: Neutral department is not blocked by anyone
            # Other departments block each other based on $BlockedDepartmentPairs
            Write-Log "Creating Block policies with neutral department: $NeutralDepartment" -Level Info
            Write-Log "Departments that will block each other: $($BlockedDepartmentPairs -join ', ')" -Level Info
            
            $policiesCreated = 0
            
            # Create bi-directional block policies between non-neutral departments
            for ($i = 0; $i -lt $BlockedDepartmentPairs.Count; $i++) {
                for ($j = $i + 1; $j -lt $BlockedDepartmentPairs.Count; $j++) {
                    $dept1 = $BlockedDepartmentPairs[$i]
                    $dept2 = $BlockedDepartmentPairs[$j]
                    
                    # Create policy: Dept1 blocks Dept2
                    $policyName1 = "$dept1 - Blocks - $dept2"
                    $existingPolicy1 = Get-InformationBarrierPolicy -Identity $policyName1 -ErrorAction SilentlyContinue
                    
                    if ($existingPolicy1) {
                        Write-Log "Policy '$policyName1' already exists. Skipping..." -Level Warning
                    }
                    else {
                        Write-Log "Creating policy: $policyName1" -Level Info
                        New-InformationBarrierPolicy -Name $policyName1 `
                            -AssignedSegment $dept1 `
                            -SegmentsBlocked @($dept2) `
                            -State "active" `
                            -ErrorAction Stop
                        Write-Log "Successfully created policy: $policyName1" -Level Success
                        $policiesCreated++
                    }
                    
                    # Create policy: Dept2 blocks Dept1
                    $policyName2 = "$dept2 - Blocks - $dept1"
                    $existingPolicy2 = Get-InformationBarrierPolicy -Identity $policyName2 -ErrorAction SilentlyContinue
                    
                    if ($existingPolicy2) {
                        Write-Log "Policy '$policyName2' already exists. Skipping..." -Level Warning
                    }
                    else {
                        Write-Log "Creating policy: $policyName2" -Level Info
                        New-InformationBarrierPolicy -Name $policyName2 `
                            -AssignedSegment $dept2 `
                            -SegmentsBlocked @($dept1) `
                            -State "active" `
                            -ErrorAction Stop
                        Write-Log "Successfully created policy: $policyName2" -Level Success
                        $policiesCreated++
                    }
                }
            }
            
            Write-Log "Created $policiesCreated new Block policies." -Level Success
            Write-Log "NOTE: '$NeutralDepartment' department remains neutral and can communicate with all departments." -Level Info
        }
        elseif ($PolicyType -eq 'Allow') {
            # Allow policies: Each department allows itself + neutral department
            # Non-neutral departments only communicate with neutral (and themselves)
            Write-Log "Creating Allow policies with neutral department: $NeutralDepartment" -Level Info
            Write-Log "Departments that will communicate with neutral: $($AllowedWithNeutralDepartments -join ', ')" -Level Info
            
            $policiesCreated = 0
            
            # Create policy for neutral department (allows itself + specified departments)
            $neutralAllowedSegments = @($NeutralDepartment) + $AllowedWithNeutralDepartments
            $neutralPolicyName = "$NeutralDepartment - Allows - $($neutralAllowedSegments -join ', ')"
            
            $existingNeutralPolicy = Get-InformationBarrierPolicy -Identity $neutralPolicyName -ErrorAction SilentlyContinue
            
            if ($existingNeutralPolicy) {
                Write-Log "Policy '$neutralPolicyName' already exists. Skipping..." -Level Warning
            }
            else {
                Write-Log "Creating neutral department policy: $neutralPolicyName" -Level Info
                New-InformationBarrierPolicy -Name $neutralPolicyName `
                    -AssignedSegment $NeutralDepartment `
                    -SegmentsAllowed $neutralAllowedSegments `
                    -State "active" `
                    -ErrorAction Stop
                Write-Log "Successfully created policy: $neutralPolicyName" -Level Success
                $policiesCreated++
            }
            
            # Create policies for non-neutral departments (each allows itself + neutral)
            foreach ($dept in $AllowedWithNeutralDepartments) {
                $allowedSegments = @($dept, $NeutralDepartment)
                $policyName = "$dept - Allows - $($allowedSegments -join ', ')"
                
                $existingPolicy = Get-InformationBarrierPolicy -Identity $policyName -ErrorAction SilentlyContinue
                
                if ($existingPolicy) {
                    Write-Log "Policy '$policyName' already exists. Skipping..." -Level Warning
                }
                else {
                    Write-Log "Creating policy: $policyName" -Level Info
                    New-InformationBarrierPolicy -Name $policyName `
                        -AssignedSegment $dept `
                        -SegmentsAllowed $allowedSegments `
                        -State "active" `
                        -ErrorAction Stop
                    Write-Log "Successfully created policy: $policyName" -Level Success
                    $policiesCreated++
                }
            }
            
            Write-Log "Created $policiesCreated new Allow policies." -Level Success
            Write-Log "NOTE: Non-neutral departments can only communicate with '$NeutralDepartment' and themselves." -Level Info
        }
        
        Write-Log "Information Barrier Policies created successfully." -Level Success
    }
    catch {
        Write-Log "Failed to create Information Barrier Policies: $($_.Exception.Message)" -Level Error
        throw
    }
    #endregion
    
    #region Apply Information Barrier Policies
    Write-Log "Starting Information Barrier Policy application..." -Level Info
    
    try {
        Start-InformationBarrierPoliciesApplication -Confirm:$false -ErrorAction Stop
        Write-Log "Policy application job started successfully. This will take approximately 1 hour to complete." -Level Success
        
        # Get initial status
        Write-Log "Retrieving policy application status..." -Level Info
        $status = Get-InformationBarrierPoliciesApplicationStatus -ErrorAction Stop
        Write-Log ($status | Out-String) -Level Info
    }
    catch {
        # Check if the error is due to an already active job
        if ($_.Exception.Message -like "*ActiveExoApplyIBPolicyJobAlreadyExistsException*" -or 
            $_.Exception.Message -like "*already an active*") {
            Write-Log "An Information Barrier policy application job is already running." -Level Warning
            Write-Log "This is expected if you recently ran this script or if a previous job is still in progress." -Level Info
            
            # Get current status of the existing job
            try {
                Write-Log "Retrieving status of the existing policy application job..." -Level Info
                $status = Get-InformationBarrierPoliciesApplicationStatus -ErrorAction Stop
                Write-Log "Current Job Status:" -Level Info
                Write-Log ($status | Out-String) -Level Info
                
                # Provide guidance based on status
                if ($status.State -eq 'Running' -or $status.State -eq 'NotStarted') {
                    Write-Log "The policy application job is currently running. Please wait for it to complete." -Level Info
                    Write-Log "Monitor progress with: Get-InformationBarrierPoliciesApplicationStatus" -Level Info
                }
                elseif ($status.State -eq 'Completed') {
                    Write-Log "The previous policy application job has completed successfully." -Level Success
                }
                elseif ($status.State -eq 'Failed') {
                    Write-Log "The previous policy application job failed. You may need to investigate and retry." -Level Warning
                }
            }
            catch {
                Write-Log "Could not retrieve policy application status: $($_.Exception.Message)" -Level Warning
            }
            
            Write-Log "Continuing with the rest of the script configuration..." -Level Info
        }
        else {
            # Different error - rethrow
            Write-Log "Failed to start or retrieve policy application: $($_.Exception.Message)" -Level Error
            throw
        }
    }
    #endregion

    #region Enable Information Barriers for SharePoint and OneDrive
    Write-Log "Enabling Information Barriers for SharePoint and OneDrive..." -Level Info
    
    try {
        Write-Log "Configuring SharePoint tenant settings for Information Barriers..." -Level Info
        
        # Enable information barriers in SharePoint and OneDrive
        Set-SPOTenant -InformationBarriersSuspension $false -ErrorAction Stop
        Write-Log "Information Barriers enabled for SharePoint and OneDrive." -Level Success
        
        # Enable Group Discoverability in SPO
        Set-SPOTenant -ShowPeoplePickerGroupSuggestionsForIB $true -ErrorAction Stop
        Write-Log "People Picker group suggestions enabled." -Level Success
        
        # Enable app bypass settings (needed for Teams Recordings)
        Set-SPOTenant -AppOnlyBypassPeoplePickerPolicies $true -ErrorAction Stop
        Set-SPOTenant -AppBypassInformationBarriers $true -ErrorAction Stop
        Write-Log "App bypass policies configured for Teams recordings." -Level Success
        
        # Enable for Teams (IBV1 Setting)
        Set-SPOTenant -IBImplicitGroupBased $true -ErrorAction Stop
        Write-Log "Implicit group-based Information Barriers enabled for Teams." -Level Success
        
        Write-Log "SharePoint and OneDrive Information Barrier configuration completed." -Level Success
    }
    catch {
        Write-Log "Failed to enable Information Barriers for SharePoint: $($_.Exception.Message)" -Level Error
        throw
    }
    #endregion
    
    #region Update OneDrive Sites with Segments
    Write-Log "Stamping existing OneDrive sites with segments..." -Level Info
    
    try {
        # Note: This cmdlet may prompt for confirmation dialog regardless of -Confirm parameter
        # User will need to click "Yes" in the confirmation dialog when it appears
        Write-Log "IMPORTANT: A confirmation dialog will appear. Please click 'Yes' to proceed with OneDrive segment updates." -Level Warning
        
        # Use -Confirm:$false (even though it may still prompt due to cmdlet implementation)
        $updateJob = Start-SPOInformationBarriersPolicyComplianceReport -UpdateOneDriveSegments -Confirm:$false -ErrorAction Stop
        Write-Log "OneDrive segment update process started. This will take approximately 1 hour to complete." -Level Success
        Write-Log ($updateJob | Out-String) -Level Verbose
    }
    catch {
        Write-Log "Failed to start OneDrive segment update: $($_.Exception.Message)" -Level Error
        throw
    }
    #endregion
    
    #region Retrieve and Display Configuration
    Write-Log "Retrieving Information Barrier configuration for validation..." -Level Info
    
    try {
        # Get Segments
        Write-Log "Retrieving organization segments..." -Level Info
        $segments = Get-OrganizationSegment -ErrorAction Stop
        Write-Log "Found $($segments.Count) organization segments:" -Level Info
        Write-Log ($segments | Format-List Name, UserGroupFilter, ExoSegmentId | Out-String) -Level Info
        
        # Get IB Policies
        Write-Log "Retrieving Information Barrier policies..." -Level Info
        $policies = Get-InformationBarrierPolicy -ErrorAction Stop
        Write-Log "Found $($policies.Count) Information Barrier policies:" -Level Info
        Write-Log ($policies | Format-List Name, AssignedSegment, SegmentsBlocked, SegmentsAllowed, ExoPolicyId, State, Guid | Out-String) -Level Info
        
        # Get Org Level Settings
        Write-Log "Retrieving organization-level Information Barrier settings..." -Level Info
        $orgConfig = Get-OrganizationConfig -ErrorAction Stop | Select-Object -Property *IB*, *info*
        Write-Log ($orgConfig | Format-List | Out-String) -Level Info
        
        $policyConfig = Get-PolicyConfig -ErrorAction Stop | Select-Object -Property *IB*, *info*
        Write-Log ($policyConfig | Format-List | Out-String) -Level Info
        
        # Get SPO Settings
        Write-Log "Retrieving SharePoint Online Information Barrier settings..." -Level Info
        $spoSettings = Get-SPOTenant -ErrorAction Stop | Select-Object DefaultOneDriveInformationBarrierMode, InformationBarriersSuspension, IBImplicitGroupBased, ShowPeoplePickerGroupSuggestionsForIB, *bypass*
        Write-Log ($spoSettings | Format-List | Out-String) -Level Info
        
        Write-Log "Configuration retrieval completed." -Level Success
    }
    catch {
        Write-Log "Failed to retrieve configuration: $($_.Exception.Message)" -Level Warning
    }
    #endregion

    #region Validate User Compatibility
    Write-Log "Testing Information Barrier compatibility between random users..." -Level Info
    
    try {
        $users = Get-CachedUsers
        
        if ($users.Count -ge 2) {
            # Test 3 random pairs for sampling
            $testCount = [Math]::Min(3, [Math]::Floor($users.Count / 2))
            
            for ($i = 1; $i -le $testCount; $i++) {
                Write-Log "Testing random user pair $i of $testCount..." -Level Info
                
                $randomUser1 = $users | Get-Random
                $randomUser2 = $users | Get-Random
                
                # Ensure we have two different users
                while ($randomUser1.UserPrincipalName -eq $randomUser2.UserPrincipalName) {
                    $randomUser2 = $users | Get-Random
                }
                
                try {
                    $results = Get-ExoInformationBarrierRelationship -RecipientId1 $randomUser1.UserPrincipalName -RecipientId2 $randomUser2.UserPrincipalName -ErrorAction Stop
                    
                    Write-Log "Compatibility Test $i Results:" -Level Info
                    Write-Log "  User 1: $($randomUser1.UserPrincipalName)" -Level Info
                    Write-Log "  User 2: $($randomUser2.UserPrincipalName)" -Level Info
                    Write-Log ($results | Out-String) -Level Info
                }
                catch {
                    Write-Log "Failed to check compatibility for test $i : $($_.Exception.Message)" -Level Warning
                }
            }
        }
        else {
            Write-Log "Not enough users to test compatibility (minimum 2 required)." -Level Warning
        }
        
        Write-Log "User compatibility testing completed." -Level Success
    }
    catch {
        Write-Log "Failed to test user compatibility: $($_.Exception.Message)" -Level Warning
    }
    #endregion
    
    #region Get Information Barrier Settings Per User
    Write-Log "Retrieving Information Barrier settings for all users..." -Level Info
    
    try {
        $users = Get-CachedUsers
        $userCount = $users.Count
        $counter = 0
        
        foreach ($user in $users) {
            $counter++
            $percentComplete = ($counter / $userCount) * 100
            Write-Progress -Activity "Retrieving IB Settings Per User" -Status "Processing $counter of $userCount" -PercentComplete $percentComplete
            
            try {
                $recipient = Get-Recipient -Identity $user.UserPrincipalName -ErrorAction Stop
                $userDetails = $recipient | Select-Object DisplayName, Name, InformationBarrierSegments, WhenIBSegmentChanged, Department, AddressBookPolicy | Format-List | Out-String
                
                # Display to console
                Write-Host "User: $($recipient.DisplayName)" -ForegroundColor Green
                Write-Host $userDetails
                
                # Also log to file
                Write-Log "User: $($recipient.DisplayName)" -Level Info -NoConsole
                Write-Log $userDetails -Level Info -NoConsole
            }
            catch {
                Write-Log "Failed to get IB settings for $($user.UserPrincipalName): $($_.Exception.Message)" -Level Warning
            }
        }
        Write-Progress -Activity "Retrieving IB Settings Per User" -Completed
        Write-Log "User Information Barrier settings retrieval completed." -Level Success
    }
    catch {
        Write-Log "Failed to retrieve user IB settings: $($_.Exception.Message)" -Level Warning
    }
    #endregion
    
    #region Get Information Barrier Settings for OneDrive Sites
    Write-Log "Retrieving Information Barrier settings for OneDrive sites..." -Level Info
    
    try {
        $odbUrls = Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'" -ErrorAction Stop | Select-Object -ExpandProperty Url
        $odbCount = $odbUrls.Count
        Write-Log "Found $odbCount OneDrive sites." -Level Info
        
        $counter = 0
        foreach ($odbUrl in $odbUrls) {
            $counter++
            $percentComplete = ($counter / $odbCount) * 100
            Write-Progress -Activity "Retrieving OneDrive IB Settings" -Status "Processing $counter of $odbCount" -PercentComplete $percentComplete
            
            try {
                $site = Get-SPOSite -Identity $odbUrl -ErrorAction Stop
                $siteDetails = $site | Select-Object Owner, URL, InformationSegment, InformationBarriersMode | Format-List | Out-String
                
                # Display to console
                Write-Host "OneDrive: $odbUrl" -ForegroundColor Cyan
                Write-Host $siteDetails
                
                # Also log to file
                Write-Log "OneDrive: $odbUrl" -Level Info -NoConsole
                Write-Log $siteDetails -Level Info -NoConsole
            }
            catch {
                Write-Log "Failed to get IB settings for $odbUrl : $($_.Exception.Message)" -Level Warning
            }
        }
        Write-Progress -Activity "Retrieving OneDrive IB Settings" -Completed
        Write-Log "OneDrive Information Barrier settings retrieval completed." -Level Success
    }
    catch {
        Write-Log "Failed to retrieve OneDrive IB settings: $($_.Exception.Message)" -Level Warning
    }
    #endregion
    
    #region Get Information Barrier Settings for SharePoint Sites
    Write-Log "Retrieving Information Barrier settings for SharePoint sites..." -Level Info
    
    try {
        $spoSites = Get-SPOSite -IncludePersonalSite $false -Limit All -ErrorAction Stop | Select-Object -ExpandProperty Url
        $siteCount = $spoSites.Count
        Write-Log "Found $siteCount SharePoint sites." -Level Info
        
        $counter = 0
        foreach ($spoSite in $spoSites) {
            $counter++
            $percentComplete = ($counter / $siteCount) * 100
            Write-Progress -Activity "Retrieving SharePoint IB Settings" -Status "Processing $counter of $siteCount" -PercentComplete $percentComplete
            
            try {
                $site = Get-SPOSite -Identity $spoSite -ErrorAction Stop
                $siteDetails = $site | Select-Object Owner, URL, InformationSegment, InformationBarriersMode | Format-List | Out-String
                
                # Display to console
                Write-Host "SharePoint Site: $spoSite" -ForegroundColor Cyan
                Write-Host $siteDetails
                
                # Also log to file
                Write-Log "SharePoint Site: $spoSite" -Level Info -NoConsole
                Write-Log $siteDetails -Level Info -NoConsole
            }
            catch {
                Write-Log "Failed to get IB settings for $spoSite : $($_.Exception.Message)" -Level Warning
            }
        }
        Write-Progress -Activity "Retrieving SharePoint IB Settings" -Completed
        Write-Log "SharePoint Information Barrier settings retrieval completed." -Level Success
    }
    catch {
        Write-Log "Failed to retrieve SharePoint IB settings: $($_.Exception.Message)" -Level Warning
    }
    #endregion
    
    #region Summary
    $script:ScriptEndTime = Get-Date
    $duration = $script:ScriptEndTime - $script:ScriptStartTime
    
    Write-Log "======================================" -Level Info
    Write-Log "Information Barriers Configuration Summary" -Level Info
    Write-Log "======================================" -Level Info
    Write-Log "Tenant: $TenantName" -Level Info
    Write-Log "Policy Type: $PolicyType" -Level Info
    Write-Log "Departments: $($Departments -join ', ')" -Level Info
    Write-Log "Start Time: $($script:ScriptStartTime)" -Level Info
    Write-Log "End Time: $($script:ScriptEndTime)" -Level Info
    Write-Log "Duration: $($duration.ToString('hh\:mm\:ss'))" -Level Info
    Write-Log "Errors: $($script:ErrorLog.Count)" -Level $(if ($script:ErrorLog.Count -gt 0) { 'Warning' } else { 'Success' })
    Write-Log "Warnings: $($script:WarningLog.Count)" -Level $(if ($script:WarningLog.Count -gt 0) { 'Warning' } else { 'Info' })
    Write-Log "Log File: $LogPath" -Level Info
    Write-Log "======================================" -Level Info
    Write-Log "IMPORTANT: Information Barrier changes may take up to 24 hours to fully propagate." -Level Warning
    Write-Log "Monitor the policy application status with: Get-InformationBarrierPoliciesApplicationStatus" -Level Info
    
    if ($script:ErrorLog.Count -gt 0) {
        Write-Log "Errors encountered during execution:" -Level Error
        foreach ($error in $script:ErrorLog) {
            Write-Log "  [$($error.Timestamp)] $($error.Message)" -Level Error
        }
    }
    
    Write-Log "Configuration completed successfully!" -Level Success
    #endregion
}
catch {
    Write-Log "FATAL ERROR: Script execution failed: $($_.Exception.Message)" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    throw
}
finally {
    Write-Log "Script execution finished." -Level Info
}

#endregion
