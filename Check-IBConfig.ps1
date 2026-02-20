<#
.SYNOPSIS
This script connects to various Microsoft 365 services and retrieves information about Information Barriers (IB) settings and policies, then exports everything to a beautiful HTML report.

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
10. Exports all collected data to a comprehensive HTML report with modern styling.

.PARAMETER TenantName
The name of the tenant (e.g., m365x61250205).

.PARAMETER Users
A list of users retrieved from the tenant.

.PARAMETER OutputPath
The path where the HTML report will be saved. Defaults to current directory.

.NOTES
Authors: Mike Lee
Date: 9/18/2024
Updated: 9/24/2025 - Added HTML report generation
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
Prompts for the tenant name and retrieves Information Barrier settings and policies for the specified tenant, then generates an HTML report.

.EXAMPLE
.\Check-IBConfig.ps1 -OutputPath "C:\Reports\IB-Report.html"
Generates the report and saves it to the specified path.
#>

param(
    [string]$OutputPath = "$env:TEMP\MyIB-Report.html"
)

# Function to check and install required modules
function Test-AndInstallModules {
    Write-Host "🔍 Checking required PowerShell modules..." -ForegroundColor Yellow
    Write-Host ""
    
    $requiredModules = @(
        @{
            Name          = "ExchangeOnlineManagement"
            DisplayName   = "Exchange Online Management"
            Description   = "Required for connecting to Exchange Online and retrieving IB settings"
            ImportCommand = "Import-Module ExchangeOnlineManagement"
        },
        @{
            Name          = "Microsoft.Online.SharePoint.PowerShell"
            DisplayName   = "SharePoint Online Management Shell"
            Description   = "Required for connecting to SharePoint Online and retrieving site settings"
            ImportCommand = "Import-Module Microsoft.Online.SharePoint.PowerShell"
        }
    )
    
    $missingModules = @()
    $installedModules = @()
    
    # Check each required module
    foreach ($module in $requiredModules) {
        Write-Host "Checking $($module.DisplayName)..." -ForegroundColor White
        
        $installedModule = Get-Module -ListAvailable -Name $module.Name -ErrorAction SilentlyContinue
        
        if ($installedModule) {
            Write-Host "  ✅ Found version: $($installedModule[0].Version)" -ForegroundColor Green
            $installedModules += $module
        }
        else {
            Write-Host "  ❌ Not installed" -ForegroundColor Red
            $missingModules += $module
        }
    }
    
    Write-Host ""
    
    # If modules are missing, offer to install them
    if ($missingModules.Count -gt 0) {
        Write-Host "⚠️  The following required modules are missing:" -ForegroundColor Yellow
        foreach ($module in $missingModules) {
            Write-Host "   • $($module.DisplayName)" -ForegroundColor White
            Write-Host "     $($module.Description)" -ForegroundColor Gray
        }
        Write-Host ""
        
        $install = Read-Host "Would you like to install the missing modules now? This requires administrator privileges. (Y/N)"
        
        if ($install -eq "Y" -or $install -eq "y" -or $install -eq "Yes" -or $install -eq "yes") {
            Write-Host "📦 Installing missing modules..." -ForegroundColor Yellow
            Write-Host ""
            
            # Check if running as administrator
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            
            if (-not $isAdmin) {
                Write-Host "⚠️  Warning: Not running as administrator. Module installation may fail." -ForegroundColor Yellow
                Write-Host "   Consider running PowerShell as Administrator for best results." -ForegroundColor Gray
                Write-Host ""
            }
            
            foreach ($module in $missingModules) {
                try {
                    Write-Host "Installing $($module.DisplayName)..." -ForegroundColor White
                    
                    # Set TLS 1.2 for PowerShell Gallery compatibility
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    
                    # Install module with proper parameters
                    if ($module.Name -eq "Microsoft.Online.SharePoint.PowerShell") {
                        Install-Module -Name $module.Name -Scope CurrentUser -AllowClobber -Force -Confirm:$false
                    }
                    else {
                        Install-Module -Name $module.Name -Scope CurrentUser -Force -Confirm:$false
                    }
                    
                    Write-Host "  ✅ Successfully installed $($module.DisplayName)" -ForegroundColor Green
                    $installedModules += $module
                }
                catch {
                    Write-Host "  ❌ Failed to install $($module.DisplayName)" -ForegroundColor Red
                    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Gray
                    Write-Host "     Please install manually using: Install-Module -Name $($module.Name)" -ForegroundColor Yellow
                    return $false
                }
            }
            
            Write-Host ""
            Write-Host "✅ All required modules are now installed!" -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "❌ Cannot continue without required modules. Please install them manually:" -ForegroundColor Red
            foreach ($module in $missingModules) {
                Write-Host "   Install-Module -Name $($module.Name)" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "Then run this script again." -ForegroundColor White
            return $false
        }
    }
    else {
        Write-Host "✅ All required modules are already installed!" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "📚 Importing modules..." -ForegroundColor Yellow
    
    # Import all required modules
    foreach ($module in $installedModules) {
        try {
            Write-Host "Importing $($module.DisplayName)..." -ForegroundColor White
            
            if ($module.Name -eq "Microsoft.Online.SharePoint.PowerShell") {
                # Special handling for SharePoint module based on PowerShell version
                if ($PSVersionTable.PSVersion.Major -gt 5) {
                    Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -Force
                }
                else {
                    Import-Module Microsoft.Online.SharePoint.PowerShell -Force
                }
            }
            else {
                Import-Module $module.Name -Force
            }
            
            Write-Host "  ✅ Successfully imported" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠️  Warning: Could not import $($module.DisplayName)" -ForegroundColor Yellow
            Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "🚀 Module check completed! Ready to proceed..." -ForegroundColor Green
    Write-Host ""
    return $true
}

# Check and install required modules before proceeding
if (-not (Test-AndInstallModules)) {
    Write-Host "Script execution stopped due to missing modules." -ForegroundColor Red
    exit 1
}

# Initialize variables to store collected data
$ReportData = @{
    TenantName         = ""
    GeneratedDate      = Get-Date
    OrgConfig          = $null
    PolicyConfig       = $null
    SPOTenant          = $null
    UserCompatibility  = @()
    UserSettings       = @()
    OneDriveSettings   = @()
    SharePointSettings = @()
    Segments           = @()
    Policies           = @()
}

# Function to generate HTML report
function New-IBReportHTML {
    param($Data, $OutputPath)
    
    $CSS = @"
<style>
    body {
        font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        margin: 0;
        padding: 20px;
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: #333;
        line-height: 1.6;
    }
    .container {
        max-width: 1200px;
        margin: 0 auto;
        background: white;
        border-radius: 10px;
        box-shadow: 0 0 20px rgba(0,0,0,0.1);
        overflow: hidden;
    }
    .header {
        background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
        color: white;
        padding: 30px;
        text-align: center;
    }
    .header h1 {
        margin: 0 0 10px 0;
        font-size: 2.5em;
        font-weight: 300;
    }
    .header p {
        margin: 0;
        opacity: 0.9;
        font-size: 1.1em;
    }
    .content {
        padding: 30px;
    }
    .section {
        margin-bottom: 40px;
        padding: 25px;
        border-radius: 8px;
        box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        border-left: 4px solid #3498db;
    }
    .section h2 {
        color: #2c3e50;
        margin-top: 0;
        margin-bottom: 20px;
        font-size: 1.8em;
        font-weight: 400;
        display: flex;
        align-items: center;
    }
    .section h2::before {
        content: '▶';
        margin-right: 10px;
        color: #3498db;
        font-size: 0.8em;
    }
    .section h3 {
        color: #34495e;
        margin: 25px 0 15px 0;
        font-size: 1.3em;
        padding-bottom: 8px;
        border-bottom: 2px solid #ecf0f1;
    }
    table {
        width: 100%;
        border-collapse: collapse;
        margin: 15px 0;
        background: white;
        border-radius: 6px;
        overflow: hidden;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    th {
        background: #34495e;
        color: white;
        padding: 15px 12px;
        text-align: left;
        font-weight: 500;
        text-transform: uppercase;
        font-size: 0.85em;
        letter-spacing: 0.5px;
    }
    td {
        padding: 12px;
        border-bottom: 1px solid #ecf0f1;
        vertical-align: top;
    }
    tr:nth-child(even) {
        background: #f8f9fa;
    }
    tr:hover {
        background: #e8f4f8;
        transition: background-color 0.3s ease;
    }
    .property {
        font-weight: 600;
        color: #2c3e50;
        min-width: 200px;
    }
    .value {
        word-break: break-word;
    }
    .status-badge {
        padding: 4px 8px;
        border-radius: 12px;
        font-size: 0.8em;
        font-weight: 500;
        text-transform: uppercase;
    }
    .status-active {
        background: #2ecc71;
        color: white;
    }
    .status-inactive {
        background: #e74c3c;
        color: white;
    }
    .status-pending {
        background: #f39c12;
        color: white;
    }
    .compatibility-allowed {
        background: #d5edda;
        color: #155724;
        padding: 8px 12px;
        border-radius: 4px;
        border-left: 4px solid #28a745;
    }
    .compatibility-blocked {
        background: #f8d7da;
        color: #721c24;
        padding: 8px 12px;
        border-radius: 4px;
        border-left: 4px solid #dc3545;
    }
    .summary-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
        gap: 20px;
        margin-bottom: 30px;
    }
    .summary-card {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        padding: 20px;
        border-radius: 8px;
        text-align: center;
        box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
    }
    .summary-card h4 {
        margin: 0 0 10px 0;
        font-size: 0.9em;
        text-transform: uppercase;
        opacity: 0.9;
    }
    .summary-card .number {
        font-size: 2.5em;
        font-weight: 300;
        margin: 0;
    }
    .footer {
        background: #ecf0f1;
        padding: 20px 30px;
        text-align: center;
        color: #7f8c8d;
        font-size: 0.9em;
    }
    .no-data {
        text-align: center;
        padding: 40px;
        color: #7f8c8d;
        font-style: italic;
    }
    @media (max-width: 768px) {
        .content { padding: 20px; }
        .header { padding: 20px; }
        .header h1 { font-size: 2em; }
        table { font-size: 0.9em; }
    }
</style>
"@

    $HTML = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Information Barriers Configuration Report - $($Data.TenantName)</title>
    $CSS
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Information Barriers Configuration Report</h1>
            <p>Tenant: <strong>$($Data.TenantName)</strong> | Generated: $($Data.GeneratedDate.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        </div>
        
        <div class="content">
"@

    # Summary cards
    $HTML += @"
            <div class="summary-grid">
                <div class="summary-card">
                    <h4>Total Segments</h4>
                    <p class="number">$($Data.Segments.Count)</p>
                </div>
                <div class="summary-card">
                    <h4>Total Policies</h4>
                    <p class="number">$($Data.Policies.Count)</p>
                </div>
                <div class="summary-card">
                    <h4>Users Analyzed</h4>
                    <p class="number">$($Data.UserSettings.Count)</p>
                </div>
                <div class="summary-card">
                    <h4>OneDrive Sites</h4>
                    <p class="number">$($Data.OneDriveSettings.Count)</p>
                </div>
            </div>
"@

    # Add each section
    $HTML += Get-OrgConfigHTML $Data
    $HTML += Get-SPOConfigHTML $Data
    $HTML += Get-UserCompatibilityHTML $Data
    $HTML += Get-SegmentsHTML $Data
    $HTML += Get-PoliciesHTML $Data
    $HTML += Get-UserSettingsHTML $Data
    $HTML += Get-OneDriveSettingsHTML $Data
    $HTML += Get-SharePointSettingsHTML $Data

    $HTML += @"
        </div>
        <div class="footer">
            <p>Generated by Check-IBConfig.ps1 | Microsoft 365 Information Barriers Report</p>
        </div>
    </div>
</body>
</html>
"@

    return $HTML
}

# Helper functions for each section
function Get-OrgConfigHTML($Data) {
    $html = @"
            <div class="section">
                <h2>Organization Configuration</h2>
"@
    
    if ($Data.OrgConfig -or $Data.PolicyConfig) {
        $html += "<table><thead><tr><th>Property</th><th>Value</th></tr></thead><tbody>"
        
        if ($Data.OrgConfig) {
            foreach ($prop in $Data.OrgConfig.PSObject.Properties) {
                if ($prop.Name -like "*IB*" -or $prop.Name -like "*Info*") {
                    $html += "<tr><td class='property'>$($prop.Name)</td><td class='value'>$($prop.Value)</td></tr>"
                }
            }
        }
        
        if ($Data.PolicyConfig) {
            foreach ($prop in $Data.PolicyConfig.PSObject.Properties) {
                if ($prop.Name -like "*IB*" -or $prop.Name -like "*Info*") {
                    $html += "<tr><td class='property'>$($prop.Name)</td><td class='value'>$($prop.Value)</td></tr>"
                }
            }
        }
        
        $html += "</tbody></table>"
    }
    else {
        $html += "<div class='no-data'>No organization configuration data available</div>"
    }
    
    $html += "</div>"
    return $html
}

function Get-SPOConfigHTML($Data) {
    $html = @"
            <div class="section">
                <h2>SharePoint Online Configuration</h2>
"@
    
    if ($Data.SPOTenant) {
        $html += "<table><thead><tr><th>Property</th><th>Value</th></tr></thead><tbody>"
        
        $spoProperties = @(
            'DefaultOneDriveInformationBarrierMode',
            'InformationBarriersSuspension',
            'IBImplicitGroupBased',
            'ShowPeoplePickerGroupSuggestionsForIB'
        )
        
        foreach ($prop in $Data.SPOTenant.PSObject.Properties) {
            if ($spoProperties -contains $prop.Name -or $prop.Name -like "*bypass*") {
                $html += "<tr><td class='property'>$($prop.Name)</td><td class='value'>$($prop.Value)</td></tr>"
            }
        }
        
        $html += "</tbody></table>"
    }
    else {
        $html += "<div class='no-data'>No SharePoint Online configuration data available</div>"
    }
    
    $html += "</div>"
    return $html
}

function Get-UserCompatibilityHTML($Data) {
    $html = @"
            <div class="section">
                <h2>User Compatibility Tests</h2>
"@
    
    if ($Data.UserCompatibility.Count -gt 0) {
        $html += "<table><thead><tr><th>User 1</th><th>User 2</th><th>Relationship</th><th>Status</th></tr></thead><tbody>"
        
        foreach ($compat in $Data.UserCompatibility) {
            $statusClass = if ($compat.Relationship -eq "Allowed") { "compatibility-allowed" } else { "compatibility-blocked" }
            $html += "<tr>"
            $html += "<td>$($compat.User1)</td>"
            $html += "<td>$($compat.User2)</td>"
            $html += "<td>$($compat.Relationship)</td>"
            $html += "<td><div class='$statusClass'>$($compat.Relationship)</div></td>"
            $html += "</tr>"
        }
        
        $html += "</tbody></table>"
    }
    else {
        $html += "<div class='no-data'>No user compatibility tests performed</div>"
    }
    
    $html += "</div>"
    return $html
}

function Get-SegmentsHTML($Data) {
    $html = @"
            <div class="section">
                <h2>Information Barrier Segments</h2>
"@
    
    if ($Data.Segments.Count -gt 0) {
        $html += "<table><thead><tr><th>Name</th><th>User Group Filter</th><th>EXO Segment ID</th></tr></thead><tbody>"
        
        foreach ($segment in $Data.Segments) {
            $html += "<tr>"
            $html += "<td class='property'>$($segment.Name)</td>"
            $html += "<td class='value'>$($segment.UserGroupFilter)</td>"
            $html += "<td>$($segment.ExoSegmentId)</td>"
            $html += "</tr>"
        }
        
        $html += "</tbody></table>"
    }
    else {
        $html += "<div class='no-data'>No segments found</div>"
    }
    
    $html += "</div>"
    return $html
}

function Get-PoliciesHTML($Data) {
    $html = @"
            <div class="section">
                <h2>Information Barrier Policies</h2>
"@
    
    if ($Data.Policies.Count -gt 0) {
        $html += "<table><thead><tr><th>Name</th><th>Assigned Segment</th><th>Segments Allowed</th><th>Segments Blocked</th><th>State</th></tr></thead><tbody>"
        
        foreach ($policy in $Data.Policies) {
            $stateClass = switch ($policy.State) {
                "Active" { "status-active" }
                "Inactive" { "status-inactive" }
                default { "status-pending" }
            }
            
            $html += "<tr>"
            $html += "<td class='property'>$($policy.Name)</td>"
            $html += "<td>$($policy.AssignedSegment)</td>"
            $html += "<td class='value'>$($policy.SegmentsAllowed -join ', ')</td>"
            $html += "<td class='value'>$($policy.SegmentsBlocked -join ', ')</td>"
            $html += "<td><span class='status-badge $stateClass'>$($policy.State)</span></td>"
            $html += "</tr>"
        }
        
        $html += "</tbody></table>"
    }
    else {
        $html += "<div class='no-data'>No policies found</div>"
    }
    
    $html += "</div>"
    return $html
}

function Get-UserSettingsHTML($Data) {
    $html = @"
            <div class="section">
                <h2>User Information Barrier Settings</h2>
"@
    
    if ($Data.UserSettings.Count -gt 0) {
        $html += "<table><thead><tr><th>Display Name</th><th>UPN</th><th>Department</th><th>IB Segments</th><th>When Changed</th></tr></thead><tbody>"
        
        foreach ($user in $Data.UserSettings) {
            $html += "<tr>"
            $html += "<td class='property'>$($user.DisplayName)</td>"
            $html += "<td class='value'>$($user.Name)</td>"
            $html += "<td>$($user.Department)</td>"
            $html += "<td class='value'>$($user.InformationBarrierSegments -join ', ')</td>"
            $html += "<td>$($user.WhenIBSegmentChanged)</td>"
            $html += "</tr>"
        }
        
        $html += "</tbody></table>"
    }
    else {
        $html += "<div class='no-data'>No user settings found</div>"
    }
    
    $html += "</div>"
    return $html
}

function Get-OneDriveSettingsHTML($Data) {
    $html = @"
            <div class="section">
                <h2>OneDrive Information Barrier Settings</h2>
"@
    
    if ($Data.OneDriveSettings.Count -gt 0) {
        $html += "<table><thead><tr><th>Owner</th><th>URL</th><th>Information Segment</th><th>IB Mode</th></tr></thead><tbody>"
        
        foreach ($site in $Data.OneDriveSettings) {
            $html += "<tr>"
            $html += "<td class='property'>$($site.Owner)</td>"
            $html += "<td class='value'><a href='$($site.URL)' target='_blank'>$($site.URL)</a></td>"
            $html += "<td>$($site.InformationSegment)</td>"
            $html += "<td>$($site.InformationBarriersMode)</td>"
            $html += "</tr>"
        }
        
        $html += "</tbody></table>"
    }
    else {
        $html += "<div class='no-data'>No OneDrive settings found</div>"
    }
    
    $html += "</div>"
    return $html
}

function Get-SharePointSettingsHTML($Data) {
    $html = @"
            <div class="section">
                <h2>SharePoint Site Information Barrier Settings</h2>
"@
    
    if ($Data.SharePointSettings.Count -gt 0) {
        $html += "<table><thead><tr><th>Owner</th><th>URL</th><th>Information Segment</th><th>IB Mode</th></tr></thead><tbody>"
        
        foreach ($site in $Data.SharePointSettings) {
            $html += "<tr>"
            $html += "<td class='property'>$($site.Owner)</td>"
            $html += "<td class='value'><a href='$($site.URL)' target='_blank'>$($site.URL)</a></td>"
            $html += "<td>$($site.InformationSegment)</td>"
            $html += "<td>$($site.InformationBarriersMode)</td>"
            $html += "</tr>"
        }
        
        $html += "</tbody></table>"
    }
    else {
        $html += "<div class='no-data'>No SharePoint site settings found</div>"
    }
    
    $html += "</div>"
    return $html
}

#Tenant
$t = Read-Host "What is your tenant name, IE: m365x61250205"
$ReportData.TenantName = $t  

#Connect to Services
Write-Host "🔗 Connecting to Microsoft 365 services..." -ForegroundColor Cyan
Write-Host ""

Write-Host "Connecting to Exchange Online..." -ForegroundColor Yellow
try {
    Connect-ExchangeOnline -ShowBanner:$false
    Write-Host "  ✅ Successfully connected to Exchange Online" -ForegroundColor Green
}
catch {
    Write-Host "  ❌ Failed to connect to Exchange Online" -ForegroundColor Red
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Gray
    Write-Host "     Please ensure you have the required permissions and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Connecting to SharePoint Online..." -ForegroundColor Yellow
try {
    Connect-SPOService -Url ('https://' + $t + '-admin.sharepoint.com')
    Write-Host "  ✅ Successfully connected to SharePoint Online" -ForegroundColor Green
}
catch {
    Write-Host "  ❌ Failed to connect to SharePoint Online" -ForegroundColor Red
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Gray
    Write-Host "     Please check your tenant name and permissions, then try again." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "✅ All service connections established successfully!" -ForegroundColor Green
Write-Host "🔍 Starting Information Barriers analysis..." -ForegroundColor Cyan

#get users parameter change be changed as needed
Write-Host "Retrieving users..." -ForegroundColor Yellow
$users = Get-User | Where-Object { $_.SKUAssigned -eq $true }

Write-Host ""

#Get Org Level Settings
Write-Host "Getting IB Org level settings" -ForegroundColor Green
$ReportData.OrgConfig = Get-OrganizationConfig | Select-Object *IB*, *info*
$ReportData.PolicyConfig = Get-PolicyConfig | Select-Object *IB*, *info*

# Display for console output
$ReportData.OrgConfig | Format-List
$ReportData.PolicyConfig | Format-List

Write-Host ""

#Check SPO Settings
Write-Host "Getting IB settings in SPO" -ForegroundColor Green
$ReportData.SPOTenant = Get-Spotenant | Select-Object DefaultOneDriveInformationBarrierMode, InformationBarriersSuspension, IBImplicitGroupBased, ShowPeoplePickerGroupSuggestionsForIB, *bypass*

# Display for console output
$ReportData.SPOTenant | Format-List

Write-Host ""

#check if users are compatible with each other:
Write-Host "Checking random user IB compatibility" -ForegroundColor Green
$randomUsers = $users | Get-Random -Count 5

foreach ($randomUser in $randomUsers) {
    $randomUser2 = $users | Get-Random
    $results = Get-ExoInformationBarrierRelationship -RecipientId1 $randomUser.UserPrincipalName -RecipientId2 $randomUser2.UserPrincipalName
    
    if ($results) {
        $r1 = $results | Select-Object RecipientName1
        $r2 = $results | Select-Object RecipientName2
        $RecipientName1 = Get-User $r1.RecipientName1 | Select-Object UserPrincipalName
        $RecipientName2 = Get-User $r2.RecipientName2 | Select-Object UserPrincipalName
        
        # Store compatibility data
        $compatibilityResult = @{
            User1           = $RecipientName1.UserPrincipalName
            User2           = $RecipientName2.UserPrincipalName
            Relationship    = $results.Relationship
            BlockedByPolicy = $results.BlockedByPolicy
            AllowedByPolicy = $results.AllowedByPolicy
        }
        $ReportData.UserCompatibility += $compatibilityResult
        
        # Display for console output
        $results 
        Write-Host "RecipientName1 is" $RecipientName1.UserPrincipalName
        Write-Host "RecipientName2 is" $RecipientName2.UserPrincipalName
    }
}

Write-Host ""

#get IB Settings per user
Write-Host "Getting IB per user" -ForegroundColor Green
foreach ($user in $users) { 
    $userIBSettings = Get-Recipient -Identity $user.UserPrincipalName | Select-Object DisplayName, name, InformationBarrierSegments, WhenIBSegmentChanged, Department, AddressBookPolicy
    $ReportData.UserSettings += $userIBSettings
    
    # Display for console output
    $userIBSettings | Format-List
}

Write-Host ""

#get IB Settings per ODB Site 
Write-Host "Getting IB Settings in OneDrive Sites" -ForegroundColor Green
$odburls = Get-SPOSite -IncludePersonalSite $true -Limit all -Filter "Url -like '-my.sharepoint.com/personal/'" | Select-Object -ExpandProperty Url
foreach ($odburl in $odburls) { 
    $odbSettings = Get-SPOSite -Identity $odburl | Select-Object Owner, URL, InformationSegment, InformationBarriersMode
    $ReportData.OneDriveSettings += $odbSettings
    
    # Display for console output
    $odbSettings | Format-List
}

Write-Host ""

#get IB Settings SPO Site
Write-Host "Getting IB Settings in SPO Sites" -ForegroundColor Green
$sposites = Get-SPOSite -IncludePersonalSite $false -Limit all | Select-Object -ExpandProperty Url
foreach ($sposite in $sposites) { 
    $spoSettings = Get-SPOSite -Identity $sposite | Select-Object Owner, URL, InformationSegment, InformationBarriersMode
    $ReportData.SharePointSettings += $spoSettings
    
    # Display for console output
    $spoSettings | Format-List
}

Write-Host ""

Write-Host "🔗 Connecting to Security & Compliance Center..." -ForegroundColor Yellow
try {
    Connect-IPPSSession -ShowBanner:$false
    Write-Host "  ✅ Successfully connected to IPPSSession" -ForegroundColor Green
}
catch {
    Write-Host "  ❌ Failed to connect to Security & Compliance Center" -ForegroundColor Red
    Write-Host "     Error: $($_.Exception.Message)" -ForegroundColor Gray
    Write-Host "     Please ensure you have the required permissions and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host ""

#Get Segments:
Write-Host "Getting IB Segments" -ForegroundColor Green
$ReportData.Segments = Get-OrganizationSegment | Select-Object name, UserGroupFilter, ExoSegmentId

# Display for console output
$ReportData.Segments | Format-List

Write-Host ""

#Get  IB Policies
Write-Host "Getting IB Policies" -ForegroundColor Green
$ReportData.Policies = Get-InformationBarrierPolicy | Select-Object Name, AssignedSegment, SegmentsBlocked, SegmentsAllowed, ExoPolicyId, State, Guid, BlockVisibility

# Display for console output
$ReportData.Policies | Format-List

Write-Host ""

# Generate timestamp for filename with more readable format
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$readableTime = Get-Date -Format "MMM dd, yyyy at HH:mm:ss"
Write-Host "📅 Generating HTML Report with timestamp: $readableTime" -ForegroundColor Yellow

# Generate HTML Report
$htmlContent = New-IBReportHTML -Data $ReportData -OutputPath $OutputPath

# Determine output path with proper validation and timestamp
if ([string]::IsNullOrEmpty($OutputPath) -or $OutputPath -eq "$env:TEMP\MyIB-Report.html") {
    $OutputPath = Join-Path (Get-Location) "IB-Report_$($t)_$timestamp.html"
}
else {
    # If custom path provided, insert timestamp before file extension
    $directory = [System.IO.Path]::GetDirectoryName($OutputPath)
    $filenameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
    $extension = [System.IO.Path]::GetExtension($OutputPath)
    $OutputPath = Join-Path $directory "$filenameWithoutExt`_$timestamp$extension"
}

# Ensure the output directory exists
$outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
if (!(Test-Path -Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

# Save the HTML report
try {
    $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Host "✅ HTML Report generated successfully!" -ForegroundColor Green
    Write-Host "📁 Report saved to: $OutputPath" -ForegroundColor Cyan
    
    # Verify file was created and has content
    if (Test-Path $OutputPath) {
        $fileSize = (Get-Item $OutputPath).Length
        Write-Host "📊 Report size: $([math]::Round($fileSize / 1KB, 2)) KB" -ForegroundColor White
        
        # Open the report in default browser
        Write-Host "🌐 Opening report in default browser..." -ForegroundColor Yellow
        try {
            # Use different methods depending on OS
            if ($IsWindows -or $env:OS -eq "Windows_NT") {
                Start-Process $OutputPath
            }
            elseif ($IsLinux) {
                Start-Process "xdg-open" -ArgumentList $OutputPath
            }
            elseif ($IsMacOS) {
                Start-Process "open" -ArgumentList $OutputPath
            }
            else {
                # Fallback method
                [System.Diagnostics.Process]::Start($OutputPath)
            }
            
            Write-Host "✅ Report opened successfully in browser!" -ForegroundColor Green
            Write-Host ""
            Write-Host "🎉 Your Information Barriers report is now ready!" -ForegroundColor Magenta
            Write-Host "   The report includes:" -ForegroundColor White
            Write-Host "   • Organization & SharePoint configuration" -ForegroundColor Gray
            Write-Host "   • Information Barrier segments and policies" -ForegroundColor Gray
            Write-Host "   • User compatibility tests and settings" -ForegroundColor Gray
            Write-Host "   • OneDrive and SharePoint site configurations" -ForegroundColor Gray
        }
        catch {
            Write-Host "⚠️  Report saved but couldn't open automatically." -ForegroundColor Yellow
            Write-Host "📂 Please manually open: $OutputPath" -ForegroundColor Cyan
            Write-Host "💡 Tip: You can copy and paste the path above into your browser" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "❌ Error: Report file was not created successfully" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Error saving HTML report: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "💾 Report content was generated but could not be saved to file." -ForegroundColor Yellow
    Write-Host "🔧 Please check:" -ForegroundColor White
    Write-Host "   • File path permissions: $OutputPath" -ForegroundColor Gray
    Write-Host "   • Available disk space" -ForegroundColor Gray
    Write-Host "   • File not in use by another program" -ForegroundColor Gray
}

Write-Host "Done........." -ForegroundColor Cyan
