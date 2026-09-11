param(
    [Parameter(Mandatory = $true)]
    [Alias('ManagedIdentityObjectId')]
    [string]$Mi,

    [Parameter(Mandatory = $false)]
    [string[]]$GraphAppPermissions = @(
        'DeviceManagementConfiguration.Read.All',
        'DeviceManagementApps.Read.All',
        'DeviceManagementServiceConfig.Read.All'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'Grant-GraphPermissions.ps1'
if (-not (Test-Path -Path $scriptPath)) {
    throw "Dependency script not found: $scriptPath"
}

Write-Host 'Granting Microsoft Graph app permissions to Automation managed identity...'
Write-Host "MI Object ID : $Mi"
Write-Host ''

& $scriptPath `
    -Mi $Mi `
    -GraphAppPermissions $GraphAppPermissions
