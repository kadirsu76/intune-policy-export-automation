param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Get-AutomationVariableValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        return Get-AutomationVariable -Name $Name -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Resolve-StringSetting {
    param(
        [Parameter(Mandatory = $true)][string]$VariableName,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$DefaultValue
    )

    $value = Get-AutomationVariableValue -Name $VariableName
    if ($null -eq $value) {
        return $DefaultValue
    }

    $text = [string]$value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $DefaultValue
    }

    return $text
}

function Resolve-IntSetting {
    param(
        [Parameter(Mandatory = $true)][string]$VariableName,
        [Parameter(Mandatory = $true)][int]$DefaultValue
    )

    $value = Get-AutomationVariableValue -Name $VariableName
    if ($null -eq $value) {
        return $DefaultValue
    }

    $text = [string]$value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $DefaultValue
    }

    $parsed = 0
    if ([int]::TryParse($text, [ref]$parsed)) {
        return $parsed
    }

    return $DefaultValue
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )

    $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "[$stamp][$Level] $Message"
}

$StorageAccountName = Resolve-StringSetting -VariableName 'IntuneExport-StorageAccountName' -DefaultValue ''
$StorageContainerName = Resolve-StringSetting -VariableName 'IntuneExport-StorageContainerName' -DefaultValue 'intune-exports'
$ExportRootPath = Resolve-StringSetting -VariableName 'IntuneExport-ExportRootPath' -DefaultValue 'daily'
$MaxRetries = Resolve-IntSetting -VariableName 'IntuneExport-MaxRetries' -DefaultValue 6
$RetryBaseDelaySeconds = Resolve-IntSetting -VariableName 'IntuneExport-RetryBaseDelaySeconds' -DefaultValue 4

if ([string]::IsNullOrWhiteSpace($StorageAccountName)) {
    throw "Automation variable 'IntuneExport-StorageAccountName' is missing or empty."
}
if ($MaxRetries -lt 1 -or $MaxRetries -gt 10) {
    throw "Automation variable 'IntuneExport-MaxRetries' must be between 1 and 10."
}
if ($RetryBaseDelaySeconds -lt 1 -or $RetryBaseDelaySeconds -gt 60) {
    throw "Automation variable 'IntuneExport-RetryBaseDelaySeconds' must be between 1 and 60."
}

function Get-EmbeddedCatalog {
    $json = @'
[
  {
    "id": "settingsCatalog",
    "area": "DeviceConfiguration",
    "subcategory": "SettingsCatalog",
    "apiVersion": "beta",
    "path": "/deviceManagement/configurationPolicies?$expand=settings",
    "assignmentPathTemplate": "/deviceManagement/configurationPolicies/{id}/assignments"
  },
  {
    "id": "deviceConfigurations",
    "area": "DeviceConfiguration",
    "subcategory": "DeviceConfigurations",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceConfigurations",
    "assignmentPathTemplate": "/deviceManagement/deviceConfigurations/{id}/assignments"
  },
  {
    "id": "groupPolicyConfigurations",
    "area": "DeviceConfiguration",
    "subcategory": "AdministrativeTemplates",
    "apiVersion": "beta",
    "path": "/deviceManagement/groupPolicyConfigurations",
    "assignmentPathTemplate": "/deviceManagement/groupPolicyConfigurations/{id}/assignments"
  },
  {
    "id": "deviceCompliancePolicies",
    "area": "Compliance",
    "subcategory": "CompliancePolicies",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceCompliancePolicies",
    "assignmentPathTemplate": "/deviceManagement/deviceCompliancePolicies/{id}/assignments"
  },
  {
    "id": "intents",
    "area": "EndpointSecurity",
    "subcategory": "SecurityPolicies",
    "apiVersion": "beta",
    "path": "/deviceManagement/intents",
    "assignmentPathTemplate": "/deviceManagement/intents/{id}/assignments"
  },
  {
    "id": "reusablePolicySettings",
    "area": "EndpointSecurity",
    "subcategory": "ReusableSettings",
    "apiVersion": "beta",
    "path": "/deviceManagement/reusablePolicySettings"
  },
  {
    "id": "windowsFeatureUpdateProfiles",
    "area": "Updates",
    "subcategory": "FeatureUpdates",
    "apiVersion": "beta",
    "path": "/deviceManagement/windowsFeatureUpdateProfiles",
    "assignmentPathTemplate": "/deviceManagement/windowsFeatureUpdateProfiles/{id}/assignments"
  },
  {
    "id": "windowsQualityUpdateProfiles",
    "area": "Updates",
    "subcategory": "QualityUpdates",
    "apiVersion": "beta",
    "path": "/deviceManagement/windowsQualityUpdateProfiles",
    "assignmentPathTemplate": "/deviceManagement/windowsQualityUpdateProfiles/{id}/assignments"
  },
  {
    "id": "windowsDriverUpdateProfiles",
    "area": "Updates",
    "subcategory": "DriverUpdates",
    "apiVersion": "beta",
    "path": "/deviceManagement/windowsDriverUpdateProfiles",
    "assignmentPathTemplate": "/deviceManagement/windowsDriverUpdateProfiles/{id}/assignments"
  },
  {
    "id": "deviceEnrollmentConfigurations",
    "area": "Enrollment",
    "subcategory": "EnrollmentConfigurations",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceEnrollmentConfigurations",
    "assignmentPathTemplate": "/deviceManagement/deviceEnrollmentConfigurations/{id}/assignments"
  },
  {
    "id": "windowsAutopilotDeploymentProfiles",
    "area": "Enrollment",
    "subcategory": "AutopilotDeploymentProfiles",
    "apiVersion": "beta",
    "path": "/deviceManagement/windowsAutopilotDeploymentProfiles",
    "assignmentPathTemplate": "/deviceManagement/windowsAutopilotDeploymentProfiles/{id}/assignments"
  },
  {
    "id": "mobileAppConfigurations",
    "area": "Applications",
    "subcategory": "AppConfigurations",
    "apiVersion": "beta",
    "path": "/deviceAppManagement/mobileAppConfigurations",
    "assignmentPathTemplate": "/deviceAppManagement/mobileAppConfigurations/{id}/assignments"
  },
  {
    "id": "targetedManagedAppConfigurations",
    "area": "Applications",
    "subcategory": "ManagedAppConfigurations",
    "apiVersion": "beta",
    "path": "/deviceAppManagement/targetedManagedAppConfigurations",
    "assignmentPathTemplate": "/deviceAppManagement/targetedManagedAppConfigurations/{id}/assignments"
  },
  {
    "id": "androidManagedAppProtections",
    "area": "Applications",
    "subcategory": "AppProtectionAndroid",
    "apiVersion": "beta",
    "path": "/deviceAppManagement/androidManagedAppProtections",
    "assignmentPathTemplate": "/deviceAppManagement/androidManagedAppProtections/{id}/assignments"
  },
  {
    "id": "iosManagedAppProtections",
    "area": "Applications",
    "subcategory": "AppProtectioniOS",
    "apiVersion": "beta",
    "path": "/deviceAppManagement/iosManagedAppProtections",
    "assignmentPathTemplate": "/deviceAppManagement/iosManagedAppProtections/{id}/assignments"
  },
  {
    "id": "mdmWindowsInformationProtectionPolicies",
    "area": "Applications",
    "subcategory": "WindowsInformationProtection",
    "apiVersion": "beta",
    "path": "/deviceAppManagement/mdmWindowsInformationProtectionPolicies",
    "assignmentPathTemplate": "/deviceAppManagement/mdmWindowsInformationProtectionPolicies/{id}/assignments"
  }
]
'@

    return $json | ConvertFrom-Json
}

function Get-ObjectValue {
    param(
        [Parameter(Mandatory = $false)][object]$Object,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $PropertyName, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $Object[$key]
            }
        }
        return $null
    }

    $prop = $Object.PSObject.Properties.Match($PropertyName) | Select-Object -First 1
    if ($null -ne $prop) {
        return $prop.Value
    }

    return $null
}

function Test-ObjectProperty {
    param(
        [Parameter(Mandatory = $false)][object]$Object,
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    if ($null -eq $Object) {
        return $false
    }

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $PropertyName, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return $false
    }

    return (($Object.PSObject.Properties.Match($PropertyName) | Measure-Object).Count -gt 0)
}

function Convert-ToOrderedMap {
    param([Parameter(Mandatory = $false)][object]$Object)

    $map = [ordered]@{}
    if ($null -eq $Object) {
        return $map
    }

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            $map[[string]$key] = $Object[$key]
        }
        return $map
    }

    foreach ($prop in $Object.PSObject.Properties) {
        $map[$prop.Name] = $prop.Value
    }

    return $map
}

function Convert-ToSingleString {
    param([Parameter(Mandatory = $false)][object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [string]) {
        return $Value
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        foreach ($entry in $Value) {
            $text = [string]$entry
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                return $text
            }
        }
        return ""
    }

    return [string]$Value
}

function Get-NextLink {
    param([Parameter(Mandatory = $true)][object]$Response)

    $next = Get-ObjectValue -Object $Response -PropertyName '@odata.nextLink'
    if (-not [string]::IsNullOrWhiteSpace([string]$next)) {
        return [string]$next
    }

    $next = Get-ObjectValue -Object $Response -PropertyName 'odata.nextLink'
    if (-not [string]::IsNullOrWhiteSpace([string]$next)) {
        return [string]$next
    }

    return $null
}

function Get-SafeName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = "Unnamed"
    }

    $safe = $Name -replace '[\\/:*?"<>|]', '_'
    if ($safe.Length -gt 80) {
        $safe = $safe.Substring(0, 80)
    }

    return $safe.Trim().TrimEnd('.')
}

function Resolve-ItemName {
    param([object]$Item)

    foreach ($nameProp in @("name", "displayName", "title", "id")) {
        $value = [string](Get-ObjectValue -Object $Item -PropertyName $nameProp)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return "Unnamed"
}

function Resolve-StatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    try {
        if ($null -ne $ErrorRecord.Exception.Response -and $null -ne $ErrorRecord.Exception.Response.StatusCode) {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
    }
    catch {
    }

    return 0
}

function Resolve-RetryAfterSeconds {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    try {
        $headers = $ErrorRecord.Exception.Response.Headers
        if ($null -eq $headers) {
            return 0
        }

        if ($headers -is [System.Collections.IDictionary]) {
            if ($headers.Contains('Retry-After')) {
                $v = $headers['Retry-After']
                if ([string]$v -match '^\d+$') {
                    return [int]$v
                }
            }
            return 0
        }

        if ($headers.PSObject.Methods.Name -contains 'TryGetValues') {
            $values = $null
            if ($headers.TryGetValues('Retry-After', [ref]$values)) {
                $candidate = @($values) | Select-Object -First 1
                if ([string]$candidate -match '^\d+$') {
                    return [int]$candidate
                }
            }
        }
    }
    catch {
        return 0
    }

    return 0
}

$script:GraphToken = $null
$script:GraphTokenExpiresOn = (Get-Date).ToUniversalTime().AddMinutes(-1)

function Resolve-AccessTokenValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$TokenValue
    )

    if ($TokenValue -is [System.Security.SecureString]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($TokenValue)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    return [string]$TokenValue
}

function Get-GraphToken {
    $now = (Get-Date).ToUniversalTime()
    if ($null -ne $script:GraphToken -and $script:GraphTokenExpiresOn -gt $now.AddMinutes(5)) {
        return $script:GraphToken
    }

    $tokenResponse = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -ErrorAction Stop
    $script:GraphToken = Resolve-AccessTokenValue -TokenValue $tokenResponse.Token
    $script:GraphTokenExpiresOn = $tokenResponse.ExpiresOn.UtcDateTime
    return $script:GraphToken
}

function Invoke-GraphGet {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $false)][switch]$AllowNotFound
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $token = Get-GraphToken
            return Invoke-RestMethod -Method GET -Uri $Uri -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json"
        }
        catch {
            $statusCode = Resolve-StatusCode -ErrorRecord $_
            if ($AllowNotFound.IsPresent -and $statusCode -eq 404) {
                return $null
            }

            $isRetryable = $statusCode -in @(408, 429, 500, 502, 503, 504)
            if (-not $isRetryable -or $attempt -eq $MaxRetries) {
                throw
            }

            $retryAfter = Resolve-RetryAfterSeconds -ErrorRecord $_
            if ($retryAfter -le 0) {
                $retryAfter = [math]::Min(120, [int]($RetryBaseDelaySeconds * [math]::Pow(2, $attempt - 1)))
            }

            Write-Log -Message "Retry $attempt/$MaxRetries for $Uri (status $statusCode), waiting $retryAfter seconds" -Level "WARN"
            Start-Sleep -Seconds $retryAfter
        }
    }

    throw "Unexpected Graph retry loop end for $Uri"
}

function Get-GraphCollection {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $results = @()
    $next = $Uri

    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $response = Invoke-GraphGet -Uri $next
        $hasCollectionValue = Test-ObjectProperty -Object $response -PropertyName 'value'
        $value = if ($hasCollectionValue) { Get-ObjectValue -Object $response -PropertyName 'value' } else { $null }

        if ($hasCollectionValue) {
            if ($null -eq $value) {
                $value = @()
            }

            if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                $results += @($value)
            }
            else {
                $results += $value
            }

            $next = Get-NextLink -Response $response
        }
        else {
            $results += $response
            $next = $null
        }
    }

    return $results
}

function Resolve-PlatformFolder {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][object]$Endpoint
    )

    if ($Endpoint.id -in @(
            "windowsFeatureUpdateProfiles",
            "windowsQualityUpdateProfiles",
            "windowsDriverUpdateProfiles",
            "windowsAutopilotDeploymentProfiles",
            "groupPolicyConfigurations",
            "intents",
            "reusablePolicySettings",
            "mdmWindowsInformationProtectionPolicies"
        )) {
        return "Windows"
    }

    if ($Endpoint.id -eq "androidManagedAppProtections") {
        return "Android"
    }

    if ($Endpoint.id -eq "iosManagedAppProtections") {
        return "iOS-iPadOS"
    }

    if ($Endpoint.id -eq "targetedManagedAppConfigurations") {
        $name = Resolve-ItemName -Item $Item
        if ($name -match '(?i)android') {
            return "Android"
        }
        if ($name -match '(?i)(ios|ipad)') {
            return "iOS-iPadOS"
        }
    }

    if ($Endpoint.id -eq "deviceEnrollmentConfigurations") {
        $configType = [string](Get-ObjectValue -Object $Item -PropertyName 'deviceEnrollmentConfigurationType')
        $enrollmentType = [string](Get-ObjectValue -Object $Item -PropertyName '@odata.type')
        $enrollmentToken = "$configType $enrollmentType".ToLowerInvariant()

        if ($enrollmentToken -match 'platformrestriction') {
            return "MultiPlatform"
        }
        if ($enrollmentToken -match 'limit') {
            return "Global"
        }
    }

    if ($Endpoint.id -eq "deviceConfigurations") {
        $configType = [string](Get-ObjectValue -Object $Item -PropertyName '@odata.type')
        $normalizedConfigType = $configType.ToLowerInvariant()
        if ($normalizedConfigType -match 'editionupgrade|sharedpc|windows|endpointprotection|bitlocker|defender|deliveryoptimization|updateforbusiness') {
            return "Windows"
        }
    }

    $tokens = @()
    foreach ($prop in @("platforms", "platform", "platformType", "devicePlatform", "osPlatform", "supportedPlatforms", "targetedPlatforms")) {
        $v = Get-ObjectValue -Object $Item -PropertyName $prop
        if ($null -eq $v) {
            continue
        }

        if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
            foreach ($x in $v) {
                if (-not [string]::IsNullOrWhiteSpace([string]$x)) {
                    $tokens += [string]$x
                }
            }
        }
        else {
            if (-not [string]::IsNullOrWhiteSpace([string]$v)) {
                $tokens += [string]$v
            }
        }
    }

    $odataType = [string](Get-ObjectValue -Object $Item -PropertyName '@odata.type')
    if (-not [string]::IsNullOrWhiteSpace($odataType)) {
        $tokens += $odataType
    }

    $folders = New-Object System.Collections.Generic.HashSet[string]
    foreach ($token in $tokens) {
        $normalized = $token.ToLowerInvariant()
        if ($normalized -match 'windows') {
            $null = $folders.Add('Windows')
        }
        elseif ($normalized -match 'linux') {
            $null = $folders.Add('Linux')
        }
        elseif ($normalized -match 'mac|osx') {
            $null = $folders.Add('macOS')
        }
        elseif ($normalized -match 'ios|ipad') {
            $null = $folders.Add('iOS-iPadOS')
        }
        elseif ($normalized -match 'android') {
            $null = $folders.Add('Android')
        }
    }

    if ($folders.Count -eq 0) {
        return "Unknown"
    }
    if ($folders.Count -gt 1) {
        return "MultiPlatform"
    }

    return ($folders | Select-Object -First 1)
}

function Get-EndpointItemPayload {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][object]$Endpoint,
        [Parameter(Mandatory = $true)][string]$ItemId
    )

    $payload = Convert-ToOrderedMap -Object $Item
    $payloadErrors = @()

    if ([string]::IsNullOrWhiteSpace($ItemId)) {
        return [pscustomobject]@{
            Payload = $payload
            Errors  = $payloadErrors
        }
    }

    if ($Endpoint.id -eq "intents") {
        $settingsUris = @(
            "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/intents/$($ItemId)/settings?`$expand=definition",
            "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/intents/$($ItemId)/settings"
        )

        $settings = @()
        $resolved = $false
        $lastMessage = ""

        foreach ($settingsUri in $settingsUris) {
            try {
                $settings = @(Get-GraphCollection -Uri $settingsUri)
                $resolved = $true
                break
            }
            catch {
                $lastMessage = $_.Exception.Message
            }
        }

        if (-not $resolved) {
            $payloadErrors += [pscustomobject]@{
                TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                EndpointId   = $Endpoint.id
                Scope        = "intent-settings"
                ItemId       = $ItemId
                Message      = $lastMessage
            }
        }

        $payload["settings"] = $settings
    }
    elseif ($Endpoint.id -eq "groupPolicyConfigurations") {
        $definitionUris = @(
            "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/groupPolicyConfigurations/$($ItemId)/definitionValues?`$expand=definition,presentationValues(`$expand=presentation)",
            "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/groupPolicyConfigurations/$($ItemId)/definitionValues?`$expand=definition,presentationValues",
            "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/groupPolicyConfigurations/$($ItemId)/definitionValues"
        )

        $definitionValues = @()
        $resolved = $false
        $lastMessage = ""

        foreach ($definitionUri in $definitionUris) {
            try {
                $definitionValues = @(Get-GraphCollection -Uri $definitionUri)
                $resolved = $true
                break
            }
            catch {
                $lastMessage = $_.Exception.Message
            }
        }

        if (-not $resolved) {
            $payloadErrors += [pscustomobject]@{
                TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                EndpointId   = $Endpoint.id
                Scope        = "groupPolicy-definitionValues"
                ItemId       = $ItemId
                Message      = $lastMessage
            }
        }

        $definitionValueItems = @()
        foreach ($definitionValue in $definitionValues) {
            $definitionValueMap = Convert-ToOrderedMap -Object $definitionValue
            $definitionValueId = [string](Get-ObjectValue -Object $definitionValue -PropertyName "id")

            if (-not [string]::IsNullOrWhiteSpace($definitionValueId)) {
                $presentationUris = @(
                    "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/groupPolicyConfigurations/$($ItemId)/definitionValues/$($definitionValueId)/presentationValues?`$expand=presentation",
                    "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/groupPolicyConfigurations/$($ItemId)/definitionValues/$($definitionValueId)/presentationValues"
                )

                $presentationValues = @()
                $presentationResolved = $false
                $presentationError = ""

                foreach ($presentationUri in $presentationUris) {
                    try {
                        $presentationValues = @(Get-GraphCollection -Uri $presentationUri)
                        $presentationResolved = $true
                        break
                    }
                    catch {
                        $presentationError = $_.Exception.Message
                    }
                }

                if ($presentationResolved) {
                    $definitionValueMap["presentationValues"] = $presentationValues
                }
                elseif (-not [string]::IsNullOrWhiteSpace($presentationError)) {
                    $payloadErrors += [pscustomobject]@{
                        TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                        EndpointId   = $Endpoint.id
                        Scope        = "groupPolicy-presentationValues"
                        ItemId       = "$ItemId/$definitionValueId"
                        Message      = $presentationError
                    }
                }
            }

            $definitionValueItems += $definitionValueMap
        }

        $payload["definitionValues"] = $definitionValueItems
    }
    elseif ($Endpoint.id -eq "reusablePolicySettings") {
        $detailUris = @(
            "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/reusablePolicySettings/$($ItemId)?`$expand=settingDefinition,settingInstance",
            "https://graph.microsoft.com/$($Endpoint.apiVersion)/deviceManagement/reusablePolicySettings/$($ItemId)"
        )

        $detail = $null
        $resolved = $false
        $lastMessage = ""

        foreach ($detailUri in $detailUris) {
            try {
                $detail = Invoke-GraphGet -Uri $detailUri
                $resolved = $true
                break
            }
            catch {
                $lastMessage = $_.Exception.Message
            }
        }

        if ($resolved -and $null -ne $detail) {
            $detailMap = Convert-ToOrderedMap -Object $detail
            foreach ($key in $detailMap.Keys) {
                $payload[$key] = $detailMap[$key]
            }
        }
        else {
            $payloadErrors += [pscustomobject]@{
                TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                EndpointId   = $Endpoint.id
                Scope        = "reusablePolicySetting-detail"
                ItemId       = $ItemId
                Message      = $lastMessage
            }
        }
    }

    return [pscustomobject]@{
        Payload = $payload
        Errors  = $payloadErrors
    }
}

function Resolve-AssignmentTarget {
    param([Parameter(Mandatory = $true)][object]$Target)

    $targetType = [string](Get-ObjectValue -Object $Target -PropertyName '@odata.type')
    $groupId = [string](Get-ObjectValue -Object $Target -PropertyName 'groupId')

    $includeExclude = 'Include'
    if ($targetType -match 'exclusion') {
        $includeExclude = 'Exclude'
    }

    $filterId = [string](Get-ObjectValue -Object $Target -PropertyName 'deviceAndAppManagementAssignmentFilterId')
    $filterType = [string](Get-ObjectValue -Object $Target -PropertyName 'deviceAndAppManagementAssignmentFilterType')

    if ([string]::IsNullOrWhiteSpace($filterId)) {
        $filterId = [string](Get-ObjectValue -Object $Target -PropertyName 'assignmentFilterId')
    }
    if ([string]::IsNullOrWhiteSpace($filterType)) {
        $filterType = [string](Get-ObjectValue -Object $Target -PropertyName 'assignmentFilterType')
    }

    return [pscustomobject]@{
        TargetType     = $targetType
        GroupId        = $groupId
        IncludeExclude = $includeExclude
        FilterId       = $filterId
        FilterType     = $filterType
    }
}

function Normalize-RelativePath {
    param([string]$Path)
    return ($Path -replace "\\", "/").TrimStart("/")
}

function Invoke-StorageUpload {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$Container,
        [Parameter(Mandatory = $true)][string]$Blob,
        [Parameter(Mandatory = $true)][string]$FilePath
    )

    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            Set-AzStorageBlobContent -Context $Context -Container $Container -Blob $Blob -File $FilePath -Force -ErrorAction Stop | Out-Null
            return
        }
        catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Seconds ([math]::Min(60, [int](3 * [math]::Pow(2, $attempt - 1))))
        }
    }
}

function Write-CsvReport {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$Columns,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ($Rows.Count -gt 0) {
        $Rows | Select-Object -Property $Columns | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
        return
    }

    Set-Content -LiteralPath $Path -Value ($Columns -join ',') -Encoding utf8
}

Write-Log -Message "Runbook started. Authenticating with managed identity."
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
$context = Get-AzContext

$catalog = Get-EmbeddedCatalog
Write-Log -Message "Endpoint catalog loaded from embedded default catalog."

$runStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$runId = [guid]::NewGuid().ToString("n").Substring(0, 8)

$datePath = (Get-Date).ToUniversalTime().ToString("yyyy/MM/dd")
$runFolder = "$runStamp-$runId"

$rootPrefix = $ExportRootPath.Trim("/")
$relativeRoot = if ([string]::IsNullOrWhiteSpace($rootPrefix)) {
    "$datePath/$runFolder"
}
else {
    "$rootPrefix/$datePath/$runFolder"
}

$tempRoot = Join-Path $env:TEMP ("intune-policy-export-" + $runId)
$reportsFolder = Join-Path $tempRoot "Reports"
New-Item -Path $reportsFolder -ItemType Directory -Force | Out-Null
trap {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    throw $_
}

$allPolicies = @()
$summaryRows = @()
$errorRows = @()
$assignmentRows = @()
$successfulEndpointCount = 0

foreach ($endpoint in $catalog) {
    $uri = "https://graph.microsoft.com/$($endpoint.apiVersion)$($endpoint.path)"
    Write-Log -Message "Exporting $($endpoint.id)"

    $items = @()
    $endpointErrors = 0
    $endpointAssignments = 0

    try {
        $items = @(Get-GraphCollection -Uri $uri)
        $successfulEndpointCount++
    }
    catch {
        $endpointErrors++
        $errorRows += [pscustomobject]@{
            TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
            EndpointId   = $endpoint.id
            Scope        = "endpoint"
            ItemId       = ""
            Message      = $_.Exception.Message
        }

        $summaryRows += [pscustomobject]@{
            EndpointId      = $endpoint.id
            Area            = $endpoint.area
            Subcategory     = $endpoint.subcategory
            ApiVersion      = $endpoint.apiVersion
            ItemCount       = 0
            AssignmentCount = 0
            ErrorCount      = $endpointErrors
        }

        continue
    }

    foreach ($item in $items) {
        $itemId = [string](Get-ObjectValue -Object $item -PropertyName "id")
        $itemName = Resolve-ItemName -Item $item
        $platform = Resolve-PlatformFolder -Item $item -Endpoint $endpoint
        $safeName = Get-SafeName -Name $itemName

        $payloadResult = Get-EndpointItemPayload -Item $item -Endpoint $endpoint -ItemId $itemId
        foreach ($payloadError in $payloadResult.Errors) {
            $endpointErrors++
            $errorRows += $payloadError
        }
        $itemPayload = $payloadResult.Payload

        $itemDir = Join-Path $tempRoot (Join-Path $platform (Join-Path $endpoint.area $endpoint.subcategory))
        New-Item -ItemType Directory -Path $itemDir -Force | Out-Null

        $fileName = if ([string]::IsNullOrWhiteSpace($itemId)) { "$safeName.json" } else { "$safeName--$itemId.json" }
        $jsonPath = Join-Path $itemDir $fileName

        $itemWritten = $false
        try {
            $itemPayload | ConvertTo-Json -Depth 100 | Out-File -LiteralPath $jsonPath -Encoding utf8
            $itemWritten = $true
        }
        catch {
            $endpointErrors++
            $errorRows += [pscustomobject]@{
                TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                EndpointId   = $endpoint.id
                Scope        = "item-json"
                ItemId       = $itemId
                Message      = $_.Exception.Message
            }
        }

        $itemAssignmentCount = 0
        $assignmentTemplate = [string](Get-ObjectValue -Object $endpoint -PropertyName "assignmentPathTemplate")
        if (-not [string]::IsNullOrWhiteSpace($assignmentTemplate) -and -not [string]::IsNullOrWhiteSpace($itemId)) {
            $assignmentUri = "https://graph.microsoft.com/$($endpoint.apiVersion)$($assignmentTemplate.Replace('{id}', $itemId))"
            try {
                $assignments = @(Get-GraphCollection -Uri $assignmentUri)
                foreach ($assignment in $assignments) {
                    $target = Get-ObjectValue -Object $assignment -PropertyName "target"
                    if ($null -eq $target) {
                        continue
                    }

                    $resolved = Resolve-AssignmentTarget -Target $target
                    $assignmentRows += [pscustomobject]@{
                        Area             = $endpoint.area
                        Subcategory      = $endpoint.subcategory
                        EndpointId       = $endpoint.id
                        PolicyId         = $itemId
                        PolicyName       = $itemName
                        AssignmentId     = [string](Get-ObjectValue -Object $assignment -PropertyName "id")
                        TargetType       = $resolved.TargetType
                        GroupId          = $resolved.GroupId
                        IncludeExclude   = $resolved.IncludeExclude
                        FilterId         = $resolved.FilterId
                        FilterType       = $resolved.FilterType
                        TargetJson       = (($target | ConvertTo-Json -Depth 20 -Compress) -replace "`r?`n", "")
                    }
                    $itemAssignmentCount++
                }
            }
            catch {
                $endpointErrors++
                $errorRows += [pscustomobject]@{
                    TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                    EndpointId   = $endpoint.id
                    Scope        = "assignments"
                    ItemId       = $itemId
                    Message      = $_.Exception.Message
                }
            }
        }

        $endpointAssignments += $itemAssignmentCount

        $relativePath = $jsonPath
        if ($jsonPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $jsonPath.Substring($tempRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
        }

        if ($itemWritten) {
            $allPolicies += [pscustomobject]@{
                Area            = $endpoint.area
                Subcategory     = $endpoint.subcategory
                EndpointId      = $endpoint.id
                PlatformFolder  = $platform
                Name            = $itemName
                Id              = $itemId
                AssignmentCount = $itemAssignmentCount
                FilePath        = Normalize-RelativePath -Path $relativePath
            }
        }
    }

    $summaryRows += [pscustomobject]@{
        EndpointId      = $endpoint.id
        Area            = $endpoint.area
        Subcategory     = $endpoint.subcategory
        ApiVersion      = $endpoint.apiVersion
        ItemCount       = $items.Count
        AssignmentCount = $endpointAssignments
        ErrorCount      = $endpointErrors
    }
}

$allPoliciesCsv = Join-Path $reportsFolder "All-Policies.csv"
$summaryCsv = Join-Path $reportsFolder "Export-Summary.csv"
$errorsCsv = Join-Path $reportsFolder "Export-Errors.csv"
$assignmentsCsv = Join-Path $reportsFolder "Assignments.csv"
$manifestPath = Join-Path $reportsFolder "manifest.json"

Write-CsvReport -Rows @($allPolicies | Sort-Object Area, Subcategory, Name) -Columns @('Area', 'Subcategory', 'EndpointId', 'PlatformFolder', 'Name', 'Id', 'AssignmentCount', 'FilePath') -Path $allPoliciesCsv
Write-CsvReport -Rows @($summaryRows | Sort-Object Area, Subcategory) -Columns @('EndpointId', 'Area', 'Subcategory', 'ApiVersion', 'ItemCount', 'AssignmentCount', 'ErrorCount') -Path $summaryCsv
Write-CsvReport -Rows $errorRows -Columns @('TimestampUtc', 'EndpointId', 'Scope', 'ItemId', 'Message') -Path $errorsCsv
Write-CsvReport -Rows @($assignmentRows | Sort-Object Area, Subcategory, PolicyName) -Columns @('Area', 'Subcategory', 'EndpointId', 'PolicyId', 'PolicyName', 'AssignmentId', 'TargetType', 'GroupId', 'IncludeExclude', 'FilterId', 'FilterType', 'TargetJson') -Path $assignmentsCsv

$tenantIdValue = Get-ObjectValue -Object $context -PropertyName "TenantId"
if ([string]::IsNullOrWhiteSpace([string]$tenantIdValue)) {
    $tenantObject = Get-ObjectValue -Object $context -PropertyName "Tenant"
    $tenantIdValue = Get-ObjectValue -Object $tenantObject -PropertyName "Id"
}

$accountValue = Get-ObjectValue -Object $context -PropertyName "Account"
$accountId = Get-ObjectValue -Object $accountValue -PropertyName "Id"
if (-not [string]::IsNullOrWhiteSpace([string]$accountId)) {
    $accountValue = $accountId
}

$manifest = [pscustomobject]@{
    generatedUtc          = (Get-Date).ToUniversalTime().ToString("o")
    tenantId              = Convert-ToSingleString -Value $tenantIdValue
    account               = Convert-ToSingleString -Value $accountValue
    endpointCount         = $catalog.Count
    totalPolicies         = $allPolicies.Count
    totalAssignments      = $assignmentRows.Count
    totalReusableSettings = (@($allPolicies | Where-Object { $_.EndpointId -eq "reusablePolicySettings" })).Count
    totalErrors           = $errorRows.Count
    successfulEndpoints   = $successfulEndpointCount
    outputRoot            = $relativeRoot
    reportsFolder         = "Reports"
}

Import-Module Az.Storage -ErrorAction Stop

$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
Get-AzStorageContainer -Context $storageContext -Name $StorageContainerName -ErrorAction Stop | Out-Null

$uploadedCount = 0
$localFiles = Get-ChildItem -Path $tempRoot -File -Recurse | Where-Object { $_.FullName -ne $manifestPath }
foreach ($file in $localFiles) {
    $relativeLocal = Normalize-RelativePath -Path $file.FullName.Substring($tempRoot.Length)
    $blobName = Normalize-RelativePath -Path "$relativeRoot/$relativeLocal"
    Invoke-StorageUpload -Context $storageContext -Container $StorageContainerName -Blob $blobName -FilePath $file.FullName
    $uploadedCount++
}

$manifest | Add-Member -NotePropertyName uploadedFiles -NotePropertyValue $uploadedCount
$manifest | Add-Member -NotePropertyName status -NotePropertyValue $(if ($successfulEndpointCount -eq 0) { 'FailedCollection' } elseif ($errorRows.Count -gt 0) { 'PartialSuccess' } else { 'Success' })
$manifest | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $manifestPath -Encoding utf8
Invoke-StorageUpload -Context $storageContext -Container $StorageContainerName -Blob (Normalize-RelativePath -Path "$relativeRoot/Reports/manifest.json") -FilePath $manifestPath
$uploadedCount++

$result = [pscustomobject]@{
    status               = if ($errorRows.Count -gt 0) { "PartialSuccess" } else { "Success" }
    runId                = $runId
    exportedItems        = $allPolicies.Count
    assignmentRows       = $assignmentRows.Count
    errorCount           = $errorRows.Count
    uploadedFiles        = $uploadedCount
    blobRoot             = $relativeRoot
    storageAccountName   = $StorageAccountName
    storageContainerName = $StorageContainerName
}

Write-Log -Message "Export completed. Policies: $($allPolicies.Count), Assignments: $($assignmentRows.Count), Errors: $($errorRows.Count), UploadedFiles: $uploadedCount"
$result | ConvertTo-Json -Depth 6

if ($successfulEndpointCount -eq 0) {
    throw 'No Graph endpoint completed successfully. Review Export-Errors.csv for details.'
}

try {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Log -Message "Temp cleanup failed: $($_.Exception.Message)" -Level "WARN"
}
