# Intune Policy Export Automation

Daily Intune configuration export automation with:

- Azure Automation schedule (daily 00:00 UTC)
- Azure Automation PowerShell 7.2 runbook (managed identity)
- Azure Storage Account blob archive (JSON + CSV + manifest)

Uses Azure Automation, managed identity, and private Blob storage.

## What it exports

The runbook exports the currently supported Intune configuration coverage (16 endpoints), including:

- Device configuration and Settings Catalog
- Endpoint Security policies
- Endpoint Security reusable settings
- Compliance policies
- Update policies
- Enrollment profiles and restrictions
- App configuration/protection/policies metadata
- Assignments with include/exclude, group ID, and assignment filter details

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

## Prerequisites

- Azure subscription with permission to deploy resources
- Intune license in tenant
- Entra admin permission to grant Graph app roles (one-time)
- Local tools for private deployment:
  - Azure CLI (`az`)
  - PowerShell 7+ (`pwsh`)

## Deploy

1. Deploy Azure resources:

```powershell
pwsh ./scripts/Deploy-Azure.ps1 -ResourceGroupName rg-intune-export -Location westeurope -BaseName intunex -RetentionDays 365
```

Resource names are derived automatically from `BaseName`:

- Automation Account: `aa-<basename>`
- Runbook: `rb-<basename>-export`
- Schedule: `sch-<basename>-daily`
- Storage Container: `<basename>-exports`
- Storage Account: auto-generated (`st<uniqueString>`) and returned as deployment output

2. Grant Graph application permissions to Automation managed identity:

```powershell
pwsh ./scripts/Grant-GraphPermissions.ps1 -Mi <automation-mi-object-id>
```

Alternative alias command:

```powershell
pwsh ./scripts/Grant-Permissions.ps1 -Mi <automation-mi-object-id>
```

`<automation-mi-object-id>` value: Azure Portal -> Automation Account (`aa-<basename>`) -> Identity -> Object (principal) ID.

3. Wait a few minutes, then start the runbook once from Portal. It has no parameters. Confirm the job is `Completed` and a new folder exists under `daily/`.

## Trigger export now (one command)

You can trigger an on-demand export immediately from CLI:

```powershell
pwsh ./scripts/Start-ExportNow.ps1 -ResourceGroupName rg-intune-export -BaseName intunex
```

Use `-Wait` to follow the job. `-SubscriptionId` selects a subscription when needed.

## Deploy to Azure button

Button (will work after repo is public, or if this file is exposed from a public deploy repo):

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkadirsu76%2Fintune-policy-export-automation%2Fmain%2Fazuredeploy.json)

Template entry file is `azuredeploy.json` in this folder. It references `infra/main.json` via `relativePath`.
Because of that, keep `infra/main.json` regenerated and committed after changing `infra/main.bicep`, `runbook/Export-IntuneConfiguration.ps1`, or `infra/publish-runbook.ps1`.

## Managed identity permissions

Minimum Graph app roles used by the helper script:

- `DeviceManagementConfiguration.Read.All`
- `DeviceManagementApps.Read.All`
- `DeviceManagementServiceConfig.Read.All`

Azure RBAC set by template:

- Automation identity -> `Storage Blob Data Contributor` on storage account

## Notes

- The template publishes the runbook and saves its settings as Automation Variables.
- Manual and scheduled runs use the same settings without parameters.
- Some endpoint failures produce `PartialSuccess` and are recorded in `Export-Errors.csv`. A run with no successful endpoints fails.
- All current Intune endpoints use Microsoft Graph `beta`.
