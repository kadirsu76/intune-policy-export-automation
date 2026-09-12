# Architecture

## Components

1. **Azure Automation Account**
   - System-assigned managed identity
   - PowerShell 7.2 runbook: `Export-IntuneConfiguration`
   - Native Automation schedule: `sch-<basename>-daily` (daily 00:00 UTC)
   - Automation Variables hold export settings, so manual starts need no parameters
   - Export logic includes pagination, retry, error isolation, and reporting

2. **Azure Storage Account (Blob)**
   - Private container for exports
   - Lifecycle policy for retention-based cleanup (default: 365 days)

3. **Deployment Script resource**
   - Publishes runbook content to Automation draft
   - Publishes runbook after draft update

## Identity and access

- No credentials or secrets in runbook.
- Runbook authenticates to:
  - Azure Resource Manager using managed identity
  - Microsoft Graph using managed identity access token
- Graph app role grants are done by admin once after deployment.

## Data flow

1. Automation schedule triggers the linked runbook job.
2. Runbook calls Graph endpoints and builds export artifacts.
3. Runbook uploads artifacts to Blob storage.
4. Job result is tracked in Azure Automation job history.

## Reliability behavior

- Graph paging via `@odata.nextLink`
- Retry for throttling/transient failures (429/5xx)
- Per-endpoint and per-item error logging
- Partial-success mode supported
