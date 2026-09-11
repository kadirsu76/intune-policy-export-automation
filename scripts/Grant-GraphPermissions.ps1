param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$AutomationAccountName,

    [Parameter(Mandatory = $false)]
    [string]$BaseName = 'intunex',

    [Parameter(Mandatory = $false)]
    [string[]]$GraphAppPermissions = @(
        'DeviceManagementConfiguration.Read.All',
        'DeviceManagementApps.Read.All',
        'DeviceManagementServiceConfig.Read.All',
        'DeviceManagementRBAC.Read.All',
        'Group.Read.All'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($AutomationAccountName)) {
    $AutomationAccountName = "aa-$($BaseName.ToLowerInvariant())"
}

function Assert-Module {
    param([string]$Name)

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing module $Name..."
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber
    }
}

Assert-Module -Name Az.Accounts
Assert-Module -Name Az.Automation
Assert-Module -Name Microsoft.Graph.Authentication
Assert-Module -Name Microsoft.Graph.Applications

Import-Module Az.Accounts
Import-Module Az.Automation
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

try {
    Get-AzContext -ErrorAction Stop | Out-Null
}
catch {
    Connect-AzAccount | Out-Null
}

$automation = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName
if ($null -eq $automation.Identity -or [string]::IsNullOrWhiteSpace($automation.Identity.PrincipalId)) {
    throw "Automation account managed identity not found. Ensure system-assigned identity is enabled."
}

$managedIdentityObjectId = [string]$automation.Identity.PrincipalId
Write-Host "Automation managed identity object id: $managedIdentityObjectId"

$requiredScopes = @(
    'Application.Read.All',
    'AppRoleAssignment.ReadWrite.All',
    'Directory.Read.All'
)

Connect-MgGraph -Scopes $requiredScopes -NoWelcome

$graphServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
if ($null -eq $graphServicePrincipal) {
    throw 'Microsoft Graph service principal not found in tenant.'
}

$miServicePrincipal = Get-MgServicePrincipal -ServicePrincipalId $managedIdentityObjectId
if ($null -eq $miServicePrincipal) {
    throw "Managed identity service principal not found: $managedIdentityObjectId"
}

$existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityObjectId -All

$results = @()

foreach ($permission in $GraphAppPermissions) {
    $appRole = $graphServicePrincipal.AppRoles |
        Where-Object { $_.Value -eq $permission -and $_.AllowedMemberTypes -contains 'Application' -and $_.IsEnabled } |
        Select-Object -First 1

    if ($null -eq $appRole) {
        $results += [pscustomobject]@{
            Permission = $permission
            Status = 'NotFound'
            AppRoleId = ''
            Message = 'App role not found in Microsoft Graph service principal.'
        }
        continue
    }

    $alreadyAssigned = $existingAssignments |
        Where-Object {
            $_.ResourceId -eq $graphServicePrincipal.Id -and
            $_.AppRoleId -eq $appRole.Id
        } |
        Select-Object -First 1

    if ($null -ne $alreadyAssigned) {
        $results += [pscustomobject]@{
            Permission = $permission
            Status = 'AlreadyAssigned'
            AppRoleId = $appRole.Id
            Message = 'Permission already assigned.'
        }
        continue
    }

    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityObjectId -BodyParameter @{
        principalId = $managedIdentityObjectId
        resourceId  = $graphServicePrincipal.Id
        appRoleId   = $appRole.Id
    } | Out-Null

    $results += [pscustomobject]@{
        Permission = $permission
        Status = 'Assigned'
        AppRoleId = $appRole.Id
        Message = 'Permission assigned successfully.'
    }
}

Write-Host ''
Write-Host 'Graph permission assignment result:'
$results | Format-Table -AutoSize

Write-Host ''
Write-Host 'Important: Managed identity tokens are cached. New permissions can take time to become effective.'
