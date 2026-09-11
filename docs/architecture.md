# Architecture

## Components

1. **Logic App (Consumption)**
   - Daily schedule trigger (03:00 Europe/Istanbul)
   - Starts Automation runbook job via ARM REST API
   - Polls job status until terminal state
   - Fails workflow on failed/suspended/stopped runbook job

2. **Azure Automation Account**
   - System-assigned managed identity
   - PowerShell 7.2 runbook: `Export-IntuneConfiguration`
   - Export logic includes pagination, retry, error isolation, and reporting

3. **Azure Storage Account (Blob)**
   - Private container for exports
   - Lifecycle policy for retention-based cleanup (default: 365 days)

4. **Deployment Script resource**
   - Publishes runbook content to Automation draft
   - Publishes runbook after draft update

## Identity and access

- No credentials or secrets in runbook.
- Runbook authenticates to:
  - Azure Resource Manager using managed identity
  - Microsoft Graph using managed identity access token
- Graph app role grants are done by admin once after deployment.

## Data flow

1. Recurrence trigger starts Logic App.
2. Logic App creates runbook job.
3. Runbook calls Graph endpoints and builds export artifacts.
4. Runbook uploads artifacts to Blob storage.
5. Logic App tracks final job state.

## Reliability behavior

- Graph paging via `@odata.nextLink`
- Retry for throttling/transient failures (429/5xx)
- Per-endpoint and per-item error logging
- Partial-success mode supported
