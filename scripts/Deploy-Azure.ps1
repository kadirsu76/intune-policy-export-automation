param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "westeurope",

    [Parameter(Mandatory = $false)]
    [string]$Prefix = "intunex",

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = "",

    [Parameter(Mandatory = $false)]
    [int]$RetentionDays = 365,

    [Parameter(Mandatory = $false)]
    [string]$AutomationAccountName = "",

    [Parameter(Mandatory = $false)]
    [string]$LogicAppName = "",

    [Parameter(Mandatory = $false)]
    [string]$RunbookName = "Export-IntuneConfiguration"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not installed or not in PATH."
    }
}

Assert-Command -Name "az"

$root = Split-Path -Path $PSScriptRoot -Parent
$templateFile = Join-Path $root "infra/main.bicep"

if (-not (Test-Path -Path $templateFile)) {
    throw "Template not found: $templateFile"
}

Write-Host "Checking Azure login state..."
try {
    az account show --output none | Out-Null
}
catch {
    Write-Host "You are not logged in. Opening Azure login..."
    az login --output none | Out-Null
}

Write-Host "Ensuring resource group exists..."
az group create --name $ResourceGroupName --location $Location --output none | Out-Null

if ([string]::IsNullOrWhiteSpace($AutomationAccountName)) {
    $AutomationAccountName = "$Prefix-aa"
}

if ([string]::IsNullOrWhiteSpace($LogicAppName)) {
    $LogicAppName = "$Prefix-la"
}

$parameters = @(
    "prefix=$Prefix"
    "location=$Location"
    "retentionDays=$RetentionDays"
    "automationAccountName=$AutomationAccountName"
    "logicAppName=$LogicAppName"
    "runbookName=$RunbookName"
)

if (-not [string]::IsNullOrWhiteSpace($StorageAccountName)) {
    $parameters += "storageAccountName=$StorageAccountName"
}

Write-Host "Deploying infrastructure from $templateFile"
az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $templateFile `
    --parameters $parameters `
    --output table

Write-Host "Deployment completed."
Write-Host "Next step: run scripts/Grant-GraphPermissions.ps1 to grant Microsoft Graph app roles to Automation managed identity."
