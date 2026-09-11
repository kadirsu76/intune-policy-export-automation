# Export Scope

## Current endpoint catalog

The endpoint catalog file is:

- `runbook/endpoint-catalog.json`

It defines endpoint metadata used by runbook:

- Area
- Subcategory
- Graph API version
- Endpoint path
- Optional assignment endpoint template

## Included domains

- DeviceConfiguration
- EndpointSecurity
- Compliance
- Updates
- Enrollment
- Applications
- Scripts
- Tenant

## Assignment coverage

When assignment endpoint exists, runbook records:

- Assignment ID
- Target type
- Group ID and display name (resolved)
- Include/Exclude state
- Assignment filter ID/type

## Platform separation

Runbook writes policies under platform roots:

- `Windows`
- `Linux`
- `macOS`
- `iOS-iPadOS`
- `Android`
- `MultiPlatform`
- `Unknown`
- `Tenant`
