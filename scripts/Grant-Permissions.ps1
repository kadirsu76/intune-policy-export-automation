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

$scriptPath = Join-Path $PSScriptRoot 'Grant-GraphPermissions.ps1'
if (-not (Test-Path -Path $scriptPath)) {
    throw "Dependency script not found: $scriptPath"
}

Write-Host 'Granting Microsoft Graph app permissions to Automation managed identity...'
Write-Host "Resource Group : $ResourceGroupName"
if ([string]::IsNullOrWhiteSpace($AutomationAccountName)) {
    $AutomationAccountName = "aa-$($BaseName.ToLowerInvariant())"
}
Write-Host "Automation    : $AutomationAccountName"
Write-Host ''

& $scriptPath `
    -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -BaseName $BaseName `
    -GraphAppPermissions $GraphAppPermissions
