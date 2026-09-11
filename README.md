# Intune Policy Export Automation

Daily Intune configuration export automation with:

- Logic App (Consumption) scheduler (03:00 Europe/Istanbul)
- Azure Automation PowerShell 7.2 runbook (managed identity)
- Azure Storage Account blob archive (JSON + CSV + manifest)

This solution is designed for private repositories first, and can be switched to one-click Deploy to Azure when repo content is public.

## What it exports

The runbook exports broad Intune configuration coverage, including:

- Device configuration and Settings Catalog
- Endpoint Security policies
- Compliance policies
- Update policies
- Enrollment profiles and restrictions
- Scripts and remediations
- App configuration/protection/policies metadata
- Assignment filters, scope tags, Intune RBAC, templates
- Assignments with include/exclude and group name resolution

It writes:

- Per-object JSON files
- `Reports/All-Policies.csv`
- `Reports/Export-Summary.csv`
- `Reports/Export-Errors.csv`
- `Reports/Assignments.csv`
- `Reports/manifest.json`

## Output structure

Blob path format:

`<exportRootPath>/<yyyy>/<MM>/<dd>/<timestamp>-<runId>/...`

Platform folders include:

- `Windows`
- `Linux`
- `macOS`
- `iOS-iPadOS`
- `Android`
- `MultiPlatform`
- `Unknown`
- `Tenant`

## Prerequisites

- Azure subscription with permission to deploy resources
- Intune license in tenant
- Entra admin permission to grant Graph app roles (one-time)
- Local tools for private deployment:
  - Azure CLI (`az`)
  - PowerShell 7+ (`pwsh`)

## Private repo deployment (current mode)

1. Deploy Azure resources:

```powershell
pwsh ./scripts/Deploy-Azure.ps1 -ResourceGroupName rg-intune-export -Location westeurope -Prefix intunex -RetentionDays 365
```

Optional pre-check:

```powershell
pwsh ./scripts/Test-Prerequisites.ps1
```

2. Grant Graph application permissions to Automation managed identity:

```powershell
pwsh ./scripts/Grant-GraphPermissions.ps1 -ResourceGroupName rg-intune-export -AutomationAccountName intunex-aa
```

Alternative alias command:

```powershell
pwsh ./scripts/Grant-Permissions.ps1 -ResourceGroupName rg-intune-export -AutomationAccountName intunex-aa
```

3. Wait a few minutes for managed identity token cache refresh.

4. Trigger Logic App manually once from Azure portal for validation.

## Deploy to Azure button

Button (will work after repo is public, or if this file is exposed from a public deploy repo):

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkadirsu76%2Fintune-policy-export-automation%2Fmain%2Fazuredeploy.json)

Template entry file is `azuredeploy.json` in this folder. It references `infra/main.json` via `relativePath`.

## Managed identity permissions

Minimum Graph app roles used by the helper script:

- `DeviceManagementConfiguration.Read.All`
- `DeviceManagementApps.Read.All`
- `DeviceManagementServiceConfig.Read.All`
- `DeviceManagementRBAC.Read.All`
- `Group.Read.All`

Azure RBAC set by template:

- Automation identity -> `Storage Blob Data Contributor` on storage account
- Logic App identity -> `Automation Job Operator` on automation account

## Notes

- Template creates and publishes runbook content during deployment using a deployment script.
- Export continues even if some endpoints fail; failures are recorded in `Export-Errors.csv`.
- Some Intune resources require Microsoft Graph `beta` endpoints; these are included by design.
