$ErrorActionPreference = 'Stop'

Import-Module Az.Accounts -ErrorAction Stop

Connect-AzAccount -Identity | Out-Null
$subscriptionId = (Get-AzContext).Subscription.Id

$resourceGroupName = $env:RG_NAME
$automationAccountName = $env:AA_NAME
$runbookName = $env:RUNBOOK_NAME
$apiVersion = $env:AUTOMATION_API_VERSION
$runbookContentBase64 = $env:RUNBOOK_CONTENT_B64
$runbookContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($runbookContentBase64))

if ([string]::IsNullOrWhiteSpace($runbookContent)) {
    throw 'RUNBOOK_CONTENT_B64 resolved to empty content. Cannot continue.'
}

$baseUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/runbooks/$runbookName"
$token = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com').Token

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
    Invoke-RestMethod -Method Put -Uri "$baseUrl/draft/content?api-version=$apiVersion" -Headers $replaceHeaders -Body $runbookContent | Out-Null
} | Out-Null

Invoke-WithRetry -ScriptBlock {
    Invoke-RestMethod -Method Post -Uri "$baseUrl/publish?api-version=$apiVersion" -Headers @{ Authorization = "Bearer $token" } | Out-Null
} | Out-Null

$published = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 5
    $state = Invoke-RestMethod -Method Get -Uri "$baseUrl?api-version=$apiVersion" -Headers @{ Authorization = "Bearer $token" }
    if ($state.properties.state -eq 'Published') {
        $published = $true
        break
    }
}

if (-not $published) {
    throw 'Runbook publish did not reach Published state in allotted time.'
}

$DeploymentScriptOutputs = @{
    runbookState = 'Published'
}
