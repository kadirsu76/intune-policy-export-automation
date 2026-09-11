# Troubleshooting

## Deployment

### Runbook not published

- Check deployment script resource logs in Azure portal.
- Confirm deployment script identity has `Automation Contributor` on Automation account.

### Schedule does not trigger runbook

- Confirm schedule `sch-<basename>-daily` exists under Automation Account -> Schedules.
- Confirm schedule next run time is in the future and UTC.
- Confirm runbook is linked in Automation Account -> Runbooks -> `rb-<basename>-export` -> Schedules.

## Runbook execution

### Graph 403 errors

- Ensure `Grant-GraphPermissions.ps1` completed successfully.
- Wait for managed identity token cache propagation.

### Storage upload errors

- Verify Automation managed identity has `Storage Blob Data Contributor` on target storage account.
- Confirm container exists and is private.

### Partial exports

- Review `Reports/Export-Errors.csv` and `Reports/Export-Summary.csv` under same run folder.
- Partial mode is expected when some beta endpoints are unavailable in tenant.

## Validation checklist

1. Manually run runbook once from Automation Account.
2. Confirm job status is `Completed` in Automation.
3. Confirm new blob folder under `daily/<yyyy>/<MM>/<dd>/...`.
4. Confirm report files exist in `Reports/`.
5. Confirm daily schedule `sch-<basename>-daily` is enabled and linked.
