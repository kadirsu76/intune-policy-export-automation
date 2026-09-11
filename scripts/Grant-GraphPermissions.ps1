param(
    [Parameter(Mandatory = $true)]
    [Alias('ManagedIdentityObjectId')]
    [string]$Mi,

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

$managedIdentityObjectId = $Mi.Trim()
if ($managedIdentityObjectId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw "Invalid -Mi value. Use managed identity Object (principal) ID GUID."
}

function Assert-Module {
    param([string]$Name)

    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Installing module $Name..."
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber
    }
}

Assert-Module -Name Microsoft.Graph.Authentication
Assert-Module -Name Microsoft.Graph.Applications

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

Write-Host "Managed identity object id: $managedIdentityObjectId"

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

$miServicePrincipal = Get-MgServicePrincipal -ServicePrincipalId $managedIdentityObjectId -ErrorAction SilentlyContinue
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
