$ErrorActionPreference = 'Stop'

Import-Module Az.Accounts -ErrorAction Stop

Connect-AzAccount -Identity | Out-Null
$subscriptionId = (Get-AzContext).Subscription.Id

$resourceGroupName = $env:RG_NAME
$automationAccountName = $env:AA_NAME
$runbookName = $env:RUNBOOK_NAME
$scheduleName = $env:SCHEDULE_NAME
$apiVersion = $env:AUTOMATION_API_VERSION
$runbookContentBase64 = $env:RUNBOOK_CONTENT_B64
$runbookContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($runbookContentBase64))

function Assert-RequiredValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Required value is empty: $Name"
    }

    return $Value.Trim()
}

$subscriptionId = Assert-RequiredValue -Name 'subscriptionId' -Value $subscriptionId
$resourceGroupName = Assert-RequiredValue -Name 'RG_NAME' -Value $resourceGroupName
$automationAccountName = Assert-RequiredValue -Name 'AA_NAME' -Value $automationAccountName
$runbookName = Assert-RequiredValue -Name 'RUNBOOK_NAME' -Value $runbookName
$scheduleName = Assert-RequiredValue -Name 'SCHEDULE_NAME' -Value $scheduleName
$apiVersion = Assert-RequiredValue -Name 'AUTOMATION_API_VERSION' -Value $apiVersion

if ([string]::IsNullOrWhiteSpace($runbookContent)) {
    throw 'RUNBOOK_CONTENT_B64 resolved to empty content. Cannot continue.'
}

$baseUrl = [System.UriBuilder]::new('https://management.azure.com').Uri.AbsoluteUri.TrimEnd('/') +
    "/subscriptions/$([Uri]::EscapeDataString($subscriptionId))/resourceGroups/$([Uri]::EscapeDataString($resourceGroupName))/providers/Microsoft.Automation/automationAccounts/$([Uri]::EscapeDataString($automationAccountName))/runbooks/$([Uri]::EscapeDataString($runbookName))"
$automationBaseUrl = $baseUrl.Substring(0, $baseUrl.LastIndexOf('/runbooks/'))
$scheduleUrl = "$automationBaseUrl/schedules/$([Uri]::EscapeDataString($scheduleName))?api-version=$apiVersion"
$jobSchedulesUrl = "$automationBaseUrl/jobSchedules?api-version=$apiVersion"

function Get-PlainTextToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceUrl
    )

    $tokenResponse = Get-AzAccessToken -ResourceUrl $ResourceUrl -ErrorAction Stop
    $tokenValue = $tokenResponse.Token

    if ($tokenValue -is [System.Security.SecureString]) {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenValue)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    return [string]$tokenValue
}

$token = Get-PlainTextToken -ResourceUrl 'https://management.azure.com/'

$replaceHeaders = @{
    Authorization = "Bearer $token"
    'Content-Type' = 'text/plain'
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 15,
        [int]$DelaySeconds = 10
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                throw
            }

            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

Invoke-WithRetry -ScriptBlock {
    Invoke-RestMethod -Method Put -Uri "${baseUrl}/draft/content?api-version=${apiVersion}" -Headers $replaceHeaders -Body $runbookContent | Out-Null
} | Out-Null

Invoke-WithRetry -ScriptBlock {
    Invoke-RestMethod -Method Post -Uri "${baseUrl}/publish?api-version=${apiVersion}" -Headers @{ Authorization = "Bearer $token" } | Out-Null
} | Out-Null

$published = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 5
    $state = Invoke-RestMethod -Method Get -Uri "${baseUrl}?api-version=${apiVersion}" -Headers @{ Authorization = "Bearer $token" }
    if ($state.properties.state -eq 'Published') {
        $published = $true
        break
    }
}

if (-not $published) {
    throw 'Runbook publish did not reach Published state in allotted time.'
}

try {
    Invoke-RestMethod -Method Get -Uri $scheduleUrl -Headers @{ Authorization = "Bearer $token" } | Out-Null
}
catch {
    $startTime = (Get-Date).ToUniversalTime().Date.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $scheduleBody = @{ properties = @{ description = 'Daily Intune policy export at 00:00 UTC'; startTime = $startTime; frequency = 'Day'; interval = 1; timeZone = 'Etc/UTC' } } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Put -Uri $scheduleUrl -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } -Body $scheduleBody | Out-Null
}

$jobSchedules = Invoke-RestMethod -Method Get -Uri $jobSchedulesUrl -Headers @{ Authorization = "Bearer $token" }
$existingLink = @($jobSchedules.value | Where-Object {
    $_.properties.runbook.name -eq $runbookName -and $_.properties.schedule.name -eq $scheduleName
} | Select-Object -First 1)

if ($existingLink.Count -eq 0) {
    $jobScheduleUrl = "$automationBaseUrl/jobSchedules/$([guid]::NewGuid())?api-version=$apiVersion"
    $jobScheduleBody = @{ properties = @{ runbook = @{ name = $runbookName }; schedule = @{ name = $scheduleName } } } | ConvertTo-Json -Depth 5 -Compress
    Invoke-RestMethod -Method Put -Uri $jobScheduleUrl -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } -Body $jobScheduleBody | Out-Null
}

$DeploymentScriptOutputs = @{
    runbookState = 'Published'
}
