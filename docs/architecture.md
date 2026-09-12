# Architecture

`sch-<basename>-daily` starts the PowerShell 7.2 runbook in `aa-<basename>` every day at 00:00 UTC.

The runbook uses its system-assigned managed identity to read Intune from Microsoft Graph and write JSON/CSV files to the private `<basename>-exports` Blob container.

Deployment publishes the runbook and stores its settings in Automation Variables. Manual starts require no parameters.
