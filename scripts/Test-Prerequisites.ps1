Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-CommandAvailable {
    param([string]$Name)

    return $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

$checks = @(
    [pscustomobject]@{ Name = 'az'; Required = $true; Description = 'Azure CLI' },
    [pscustomobject]@{ Name = 'pwsh'; Required = $true; Description = 'PowerShell 7+' }
)

foreach ($check in $checks) {
    $ok = Test-CommandAvailable -Name $check.Name
    $status = if ($ok) { 'OK' } else { 'MISSING' }
    Write-Host ("{0,-8} {1,-20} {2}" -f $status, $check.Name, $check.Description)

    if ($check.Required -and -not $ok) {
        throw "Required tool is missing: $($check.Name)"
    }
}

Write-Host ''
Write-Host 'Checking Azure login...'
try {
    az account show --output none | Out-Null
    Write-Host 'OK      Azure login session found.'
}
catch {
    Write-Host 'MISSING Azure login session. Run: az login'
}

Write-Host ''
Write-Host 'Checking PowerShell modules for Graph permission script...'

$modules = @(
    'Az.Accounts',
    'Az.Automation',
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications'
)

foreach ($moduleName in $modules) {
    $found = Get-Module -ListAvailable -Name $moduleName
    $status = if ($null -ne $found) { 'OK' } else { 'MISSING' }
    Write-Host ("{0,-8} {1}" -f $status, $moduleName)
}
