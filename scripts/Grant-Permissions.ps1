param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$AutomationAccountName,

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

$scriptPath = Join-Path $PSScriptRoot 'Grant-GraphPermissions.ps1'
if (-not (Test-Path -Path $scriptPath)) {
    throw "Dependency script not found: $scriptPath"
}

Write-Host 'Granting Microsoft Graph app permissions to Automation managed identity...'
Write-Host "Resource Group : $ResourceGroupName"
Write-Host "Automation    : $AutomationAccountName"
Write-Host ''

& $scriptPath `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -GraphAppPermissions $GraphAppPermissions
