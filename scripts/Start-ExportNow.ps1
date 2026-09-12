param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$BaseName = 'intunex',

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $false)]
    [string]$StorageContainerName,

    [Parameter(Mandatory = $false)]
    [string]$ExportRootPath,

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

function Ensure-AzLogin {
    try {
        az account show --output none | Out-Null
    }
    catch {
        Write-Host 'No active Azure CLI login. Opening az login...'
        az login --output none | Out-Null
    }
}

function Invoke-AzRestJson {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'PUT')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $false)][string]$BodyJson
    )

    if ([string]::IsNullOrWhiteSpace($BodyJson)) {
        $raw = az rest --method $Method --url $Url --output json
    }
    else {
        $raw = az rest --method $Method --url $Url --headers 'Content-Type=application/json' --body $BodyJson --output json
    }

    return ($raw | ConvertFrom-Json)
}

function Get-MapValue {
    param(
        [Parameter(Mandatory = $false)][object]$Map,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Map) {
        return $null
    }

    if ($Map -is [System.Collections.IDictionary]) {
        foreach ($key in $Map.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $Map[$key]
            }
        }

        return $null
    }

    $property = $Map.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}

Assert-Command -Name 'az'
Ensure-AzLogin

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

if ([string]::IsNullOrWhiteSpace($StorageAccountName) -or [string]::IsNullOrWhiteSpace($StorageContainerName) -or [string]::IsNullOrWhiteSpace($ExportRootPath)) {
    $jobsUrl = "https://management.azure.com/subscriptions/${subscriptionIdValue}/resourceGroups/${ResourceGroupName}/providers/Microsoft.Automation/automationAccounts/${automationAccountName}/jobs?api-version=2024-10-23"
    $jobs = Invoke-AzRestJson -Method 'GET' -Url $jobsUrl

    $runbookJobs = @($jobs.value | Where-Object {
        [string](Get-MapValue -Map (Get-MapValue -Map $_ -Name 'properties') -Name 'runbook' | ForEach-Object { Get-MapValue -Map $_ -Name 'name' }) -eq $runbookName
    } | Sort-Object {
        [DateTime](Get-MapValue -Map (Get-MapValue -Map $_ -Name 'properties') -Name 'creationTime')
    } -Descending)

    foreach ($runbookJob in $runbookJobs) {
        $runbookJobName = [string](Get-MapValue -Map $runbookJob -Name 'name')
        if ([string]::IsNullOrWhiteSpace($runbookJobName)) {
            continue
        }

        $jobUrl = "https://management.azure.com/subscriptions/${subscriptionIdValue}/resourceGroups/${ResourceGroupName}/providers/Microsoft.Automation/automationAccounts/${automationAccountName}/jobs/${runbookJobName}?api-version=2024-10-23"
        $jobDetails = Invoke-AzRestJson -Method 'GET' -Url $jobUrl
        $jobProperties = Get-MapValue -Map $jobDetails -Name 'properties'
        $jobParams = Get-MapValue -Map $jobProperties -Name 'parameters'

        if ($null -eq $jobParams) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
            $StorageAccountName = [string](Get-MapValue -Map $jobParams -Name 'StorageAccountName')
        }
        if ([string]::IsNullOrWhiteSpace($StorageContainerName)) {
            $StorageContainerName = [string](Get-MapValue -Map $jobParams -Name 'StorageContainerName')
        }
        if ([string]::IsNullOrWhiteSpace($ExportRootPath)) {
            $ExportRootPath = [string](Get-MapValue -Map $jobParams -Name 'ExportRootPath')
        }

        if (-not [string]::IsNullOrWhiteSpace($StorageAccountName) -and -not [string]::IsNullOrWhiteSpace($StorageContainerName) -and -not [string]::IsNullOrWhiteSpace($ExportRootPath)) {
            break
        }
    }

    $jobSchedulesUrl = "https://management.azure.com/subscriptions/${subscriptionIdValue}/resourceGroups/${ResourceGroupName}/providers/Microsoft.Automation/automationAccounts/${automationAccountName}/jobSchedules?api-version=2024-10-23"
    $jobSchedules = Invoke-AzRestJson -Method 'GET' -Url $jobSchedulesUrl

    $matchingSchedule = @($jobSchedules.value | Where-Object {
        $scheduleProperties = Get-MapValue -Map $_ -Name 'properties'
        $scheduleRunbook = Get-MapValue -Map (Get-MapValue -Map $scheduleProperties -Name 'runbook') -Name 'name'
        $scheduleParams = Get-MapValue -Map $scheduleProperties -Name 'parameters'
        $scheduleStorage = Get-MapValue -Map $scheduleParams -Name 'StorageAccountName'

        [string]$scheduleRunbook -eq $runbookName -and -not [string]::IsNullOrWhiteSpace([string]$scheduleStorage)
    } | Select-Object -First 1)

    if ($matchingSchedule.Count -gt 0) {
        $scheduleParams = $matchingSchedule[0].properties.parameters

        if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
            $StorageAccountName = [string](Get-MapValue -Map $scheduleParams -Name 'StorageAccountName')
        }
        if ([string]::IsNullOrWhiteSpace($StorageContainerName)) {
            $StorageContainerName = [string](Get-MapValue -Map $scheduleParams -Name 'StorageContainerName')
        }
        if ([string]::IsNullOrWhiteSpace($ExportRootPath)) {
            $ExportRootPath = [string](Get-MapValue -Map $scheduleParams -Name 'ExportRootPath')
        }
    }
}

if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
    $automationAccountUrl = "https://management.azure.com/subscriptions/${subscriptionIdValue}/resourceGroups/${ResourceGroupName}/providers/Microsoft.Automation/automationAccounts/${automationAccountName}?api-version=2023-11-01"
    $automationAccount = Invoke-AzRestJson -Method 'GET' -Url $automationAccountUrl
    $automationPrincipalId = [string](Get-MapValue -Map $automationAccount.identity -Name 'principalId')

    if (-not [string]::IsNullOrWhiteSpace($automationPrincipalId)) {
        $scopesRaw = az role assignment list --subscription $subscriptionIdValue --assignee-object-id $automationPrincipalId --all --query "[?roleDefinitionName=='Storage Blob Data Contributor' && contains(scope, '/providers/Microsoft.Storage/storageAccounts/')].scope" --output json
        $scopes = @($scopesRaw | ConvertFrom-Json)

        foreach ($scope in $scopes) {
            if ([string]$scope -match '/storageAccounts/([^/]+)') {
                $StorageAccountName = $matches[1]
                break
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($StorageContainerName)) {
    $StorageContainerName = "$normalizedBaseName-exports"
}
if ([string]::IsNullOrWhiteSpace($ExportRootPath)) {
    $ExportRootPath = 'daily'
}
if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
    throw "StorageAccountName could not be auto-detected. Re-run with -StorageAccountName <name>."
}

$jobName = [guid]::NewGuid().ToString()
$createJobUrl = "https://management.azure.com/subscriptions/${subscriptionIdValue}/resourceGroups/${ResourceGroupName}/providers/Microsoft.Automation/automationAccounts/${automationAccountName}/jobs/${jobName}?api-version=2024-10-23"

$jobBody = @{
    properties = @{
        runbook = @{
            name = $runbookName
        }
        parameters = @{
            StorageAccountName   = $StorageAccountName
            StorageContainerName = $StorageContainerName
            ExportRootPath       = $ExportRootPath
        }
    }
}

$null = Invoke-AzRestJson -Method 'PUT' -Url $createJobUrl -BodyJson ($jobBody | ConvertTo-Json -Depth 8 -Compress)

Write-Host 'Export job started.'
Write-Host "Subscription      : $subscriptionIdValue"
Write-Host "Resource Group    : $ResourceGroupName"
Write-Host "Automation Account: $automationAccountName"
Write-Host "Runbook           : $runbookName"
Write-Host "Job Name          : $jobName"
Write-Host "Storage Account   : $StorageAccountName"
Write-Host "Container         : $StorageContainerName"
Write-Host "ExportRootPath    : $ExportRootPath"

if (-not $Wait.IsPresent) {
    return
}

$terminalStatuses = @('Completed', 'Failed', 'Stopped', 'Suspended', 'Blocked')
$lastStatus = ''
$jobUrl = "https://management.azure.com/subscriptions/${subscriptionIdValue}/resourceGroups/${ResourceGroupName}/providers/Microsoft.Automation/automationAccounts/${automationAccountName}/jobs/${jobName}?api-version=2024-10-23"

while ($true) {
    Start-Sleep -Seconds $PollSeconds
    $job = Invoke-AzRestJson -Method 'GET' -Url $jobUrl
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
