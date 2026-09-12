# Troubleshooting

**Graph 403:** Run `Grant-GraphPermissions.ps1`, then wait a few minutes for token refresh.

**Storage error:** Confirm the Automation identity has `Storage Blob Data Contributor` on the export storage account.

**Partial export:** Check `Reports/Export-Errors.csv` in the same export folder.

**Schedule issue:** Confirm `sch-<basename>-daily` is enabled and linked to `rb-<basename>-export`.
