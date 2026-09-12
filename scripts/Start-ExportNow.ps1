param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$BaseName = 'intunex',

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$Wait,

    [Parameter(Mandatory = $false)]
    [ValidateRange(5, 300)]
    [int]$PollSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not installed or not in PATH."
    }
}

Assert-Command -Name 'az'

try {
    az account show --output none | Out-Null
}
catch {
    Write-Host 'No active Azure CLI login. Opening az login...'
    az login --output none | Out-Null
}

if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    az account set --subscription $SubscriptionId
}

$subscriptionIdValue = az account show --query id --output tsv
if ([string]::IsNullOrWhiteSpace($subscriptionIdValue)) {
    throw 'Unable to resolve current Azure subscription from az account show.'
}

$normalizedBaseName = $BaseName.ToLowerInvariant().Replace('_', '-')
$automationAccountName = "aa-$normalizedBaseName"
$runbookName = "rb-$normalizedBaseName-export"
$jobName = [guid]::NewGuid().ToString()
$jobUrl = "https://management.azure.com/subscriptions/${subscriptionIdValue}/resourceGroups/${ResourceGroupName}/providers/Microsoft.Automation/automationAccounts/${automationAccountName}/jobs/${jobName}?api-version=2024-10-23"
$jobBody = '{"properties":{"runbook":{"name":"' + $runbookName + '"}}}'

$raw = az rest --method put --url $jobUrl --headers 'Content-Type=application/json' --body $jobBody --output json
$null = $raw | ConvertFrom-Json

Write-Host 'Export job started.'
Write-Host "Subscription      : $subscriptionIdValue"
Write-Host "Resource Group    : $ResourceGroupName"
Write-Host "Automation Account: $automationAccountName"
Write-Host "Runbook           : $runbookName"
Write-Host "Job Name          : $jobName"

if (-not $Wait.IsPresent) {
    return
}

$terminalStatuses = @('Completed', 'Failed', 'Stopped', 'Suspended', 'Blocked')
$lastStatus = ''

while ($true) {
    Start-Sleep -Seconds $PollSeconds
    $raw = az rest --method get --url $jobUrl --output json
    $job = $raw | ConvertFrom-Json
    $status = [string]$job.properties.status

    if ($status -ne $lastStatus) {
        Write-Host "Job status: $status"
        $lastStatus = $status
    }

    if ($terminalStatuses -contains $status) {
        if ($status -ne 'Completed') {
            $exceptionText = [string]$job.properties.exception
            if ([string]::IsNullOrWhiteSpace($exceptionText)) {
                throw "Export job finished with status '$status'."
            }

            throw "Export job finished with status '$status'. Exception: $exceptionText"
        }

        Write-Host 'Export job completed successfully.'
        break
    }
}
