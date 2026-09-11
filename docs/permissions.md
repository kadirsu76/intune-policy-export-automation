# Permissions

## Azure RBAC (set by template)

1. **Automation managed identity**
   - Scope: Storage Account
   - Role: `Storage Blob Data Contributor`

2. **Logic App managed identity**
   - Scope: Automation Account
   - Role: `Automation Job Operator`

## Microsoft Graph app roles (one-time admin task)

Run:

```powershell
pwsh ./scripts/Grant-GraphPermissions.ps1 -Mi <automation-mi-object-id>
```

Find MI object id:

- Automation Account (`aa-<basename>`) -> Identity -> Object (principal) ID

Default app roles granted:

- `DeviceManagementConfiguration.Read.All`
- `DeviceManagementApps.Read.All`
- `DeviceManagementServiceConfig.Read.All`

Required admin consent scopes for this script session:

- `Application.Read.All`
- `AppRoleAssignment.ReadWrite.All`
- `Directory.Read.All`

## Token cache note

Managed identity tokens are cached by platform services. New Graph grants may require several minutes before they become effective in runbook calls.
