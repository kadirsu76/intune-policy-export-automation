# Export Scope

## Coverage

The deployed runbook contains the 16 supported endpoint definitions. `runbook/endpoint-catalog.json` is the readable reference copy.

Each definition includes:

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

Current endpoint count: 16.

## Assignment coverage

When assignment endpoint exists, runbook records:

- Assignment ID
- Target type
- Group ID
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
- `Global`
