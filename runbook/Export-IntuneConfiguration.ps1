param(
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $false)]
    [string]$StorageContainerName = "intune-exports",

    [Parameter(Mandatory = $false)]
    [string]$ExportRootPath = "daily",

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 6,

    [Parameter(Mandatory = $false)]
    [int]$RetryBaseDelaySeconds = 4,

    [Parameter(Mandatory = $false)]
    [string]$EndpointCatalogJson = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )

    $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Output "[$stamp][$Level] $Message"
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
    "id": "templates",
    "area": "EndpointSecurity",
    "subcategory": "Templates",
    "apiVersion": "beta",
    "path": "/deviceManagement/templates"
  },
  {
    "id": "deviceManagementScripts",
    "area": "Scripts",
    "subcategory": "WindowsPowerShellScripts",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceManagementScripts",
    "assignmentPathTemplate": "/deviceManagement/deviceManagementScripts/{id}/assignments"
  },
  {
    "id": "deviceShellScripts",
    "area": "Scripts",
    "subcategory": "macOSShellScripts",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceShellScripts",
    "assignmentPathTemplate": "/deviceManagement/deviceShellScripts/{id}/assignments"
  },
  {
    "id": "deviceCustomAttributeShellScripts",
    "area": "Scripts",
    "subcategory": "CustomAttributeScripts",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceCustomAttributeShellScripts"
  },
  {
    "id": "deviceHealthScripts",
    "area": "Scripts",
    "subcategory": "ProactiveRemediations",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceHealthScripts",
    "assignmentPathTemplate": "/deviceManagement/deviceHealthScripts/{id}/assignments"
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
    "id": "deviceEnrollmentNotificationsConfiguration",
    "area": "Enrollment",
    "subcategory": "EnrollmentNotifications",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceEnrollmentNotificationsConfiguration"
  },
  {
    "id": "deviceCategories",
    "area": "Tenant",
    "subcategory": "DeviceCategories",
    "apiVersion": "beta",
    "path": "/deviceManagement/deviceCategories"
  },
  {
    "id": "assignmentFilters",
    "area": "Tenant",
    "subcategory": "AssignmentFilters",
    "apiVersion": "beta",
    "path": "/deviceManagement/assignmentFilters"
  },
  {
    "id": "roleDefinitions",
    "area": "Tenant",
    "subcategory": "RBACRoleDefinitions",
    "apiVersion": "beta",
    "path": "/deviceManagement/roleDefinitions"
  },
  {
    "id": "roleAssignments",
    "area": "Tenant",
    "subcategory": "RBACRoleAssignments",
    "apiVersion": "beta",
    "path": "/deviceManagement/roleAssignments"
  },
  {
    "id": "scopeTags",
    "area": "Tenant",
    "subcategory": "ScopeTags",
    "apiVersion": "beta",
    "path": "/deviceManagement/roleScopeTags"
  },
  {
    "id": "notificationMessageTemplates",
    "area": "Tenant",
    "subcategory": "NotificationTemplates",
    "apiVersion": "beta",
    "path": "/deviceManagement/notificationMessageTemplates"
  },
  {
    "id": "termsAndConditions",
    "area": "Tenant",
    "subcategory": "TermsAndConditions",
    "apiVersion": "beta",
    "path": "/deviceManagement/termsAndConditions"
  },
  {
    "id": "complianceManagementPartners",
    "area": "Tenant",
    "subcategory": "CompliancePartners",
    "apiVersion": "beta",
    "path": "/deviceManagement/complianceManagementPartners"
  },
  {
    "id": "mobileApps",
    "area": "Applications",
    "subcategory": "MobileApps",
    "apiVersion": "beta",
    "path": "/deviceAppManagement/mobileApps",
    "assignmentPathTemplate": "/deviceAppManagement/mobileApps/{id}/assignments"
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
    "id": "managedAppPolicies",
    "area": "Applications",
    "subcategory": "ManagedAppPolicies",
    "apiVersion": "beta",
    "path": "/deviceAppManagement/managedAppPolicies"
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

function Get-SafeName {
    param([string]$Name)

    $value = if ([string]::IsNullOrWhiteSpace($Name)) { "Unnamed" } else { $Name.Trim() }
    $value = $value -replace '[\\/:*?"<>|]', "_"
    $value = $value -replace '\s+', " "
    if ($value.Length -gt 100) {
        $value = $value.Substring(0, 100)
    }
    return $value.Trim()
}

function Resolve-ItemName {
    param([object]$Item)

    foreach ($key in @("name", "displayName", "title")) {
        $value = Get-PropertyIfExists -Item $Item -PropertyName $key
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }

    $itemId = Get-PropertyIfExists -Item $Item -PropertyName "id"
    if ($null -ne $itemId) {
        return [string]$itemId
    }

    return "Unnamed"
}

function Get-PropertyIfExists {
    param(
        [object]$Item,
        [string]$PropertyName
    )

    if ($null -eq $Item) {
        return $null
    }

    if ($Item.PSObject.Properties.Name -contains $PropertyName) {
        return $Item.$PropertyName
    }

    return $null
}

function Resolve-PlatformFolder {
    param(
        [string]$Area,
        [object]$Item
    )

    if ($Area -eq "Tenant") {
        return "Tenant"
    }

    $sources = [System.Collections.Generic.List[string]]::new()

    $platforms = Get-PropertyIfExists -Item $Item -PropertyName "platforms"
    if ($platforms -is [System.Array]) {
        foreach ($p in $platforms) {
            if ($null -ne $p) {
                $sources.Add([string]$p)
            }
        }
    }
    elseif ($null -ne $platforms) {
        $sources.Add([string]$platforms)
    }

    foreach ($propertyName in @("platform", "platformType", "devicePlatform", "osPlatform", "operatingSystem")) {
        $value = Get-PropertyIfExists -Item $Item -PropertyName $propertyName
        if ($null -ne $value) {
            $sources.Add([string]$value)
        }
    }

    $odataType = Get-PropertyIfExists -Item $Item -PropertyName "@odata.type"
    if ($null -ne $odataType) {
        $sources.Add([string]$odataType)
    }

    $normalized = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $sources) {
        $text = ([string]$entry).ToLowerInvariant()
        if ($text.Contains("windows")) { [void]$normalized.Add("Windows") }
        if ($text.Contains("linux")) { [void]$normalized.Add("Linux") }
        if ($text.Contains("mac") -or $text.Contains("osx")) { [void]$normalized.Add("macOS") }
        if ($text.Contains("ios") -or $text.Contains("ipad")) { [void]$normalized.Add("iOS-iPadOS") }
        if ($text.Contains("android")) { [void]$normalized.Add("Android") }
    }

    if ($normalized.Count -eq 0) {
        return "Unknown"
    }

    if ($normalized.Count -gt 1) {
        return "MultiPlatform"
    }

    return ($normalized | Select-Object -First 1)
}

function Resolve-StatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    try {
        if ($null -ne $ErrorRecord.Exception.Response -and $null -ne $ErrorRecord.Exception.Response.StatusCode) {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
    }
    catch {
        return $null
    }

    return $null
}

function Resolve-RetryAfterSeconds {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    try {
        $headers = $ErrorRecord.Exception.Response.Headers
        if ($null -eq $headers) {
            return 0
        }

        $retryAfter = $headers["Retry-After"]
        if ($null -eq $retryAfter) {
            return 0
        }

        $candidate = $retryAfter | Select-Object -First 1
        if ($candidate -match "^\d+$") {
            return [int]$candidate
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
                $retryAfter = [math]::Min(120, $RetryBaseDelaySeconds * [math]::Pow(2, $attempt - 1))
            }

            Write-Log -Message "Graph retry $attempt/$MaxRetries for $Uri (status $statusCode). Waiting $retryAfter seconds." -Level "WARN"
            Start-Sleep -Seconds $retryAfter
        }
    }
}

function Get-GraphCollection {
    param(
        [Parameter(Mandatory = $true)][string]$ApiVersion,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][switch]$AllowNotFound
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $nextUri = "https://graph.microsoft.com/$ApiVersion$Path"

    while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
        $response = Invoke-GraphGet -Uri $nextUri -AllowNotFound:$AllowNotFound.IsPresent
        if ($null -eq $response) {
            break
        }

        if ($response.PSObject.Properties.Name -contains "value") {
            foreach ($item in $response.value) {
                [void]$items.Add($item)
            }
            $nextUri = $response.'@odata.nextLink'
        }
        else {
            [void]$items.Add($response)
            $nextUri = $null
        }
    }

    return $items
}

function Get-SettingCount {
    param([object]$Item)

    $settings = Get-PropertyIfExists -Item $Item -PropertyName "settings"
    if ($settings -is [System.Array]) {
        return $settings.Count
    }
    if ($null -eq $settings) {
        return 0
    }
    return 1
}

function Resolve-AssignmentTarget {
    param(
        [object]$Assignment,
        [hashtable]$GroupCache
    )

    $target = Get-PropertyIfExists -Item $Assignment -PropertyName "target"
    if ($null -eq $target) {
        return [pscustomobject]@{
            TargetType = "Unknown"
            TargetValue = "Unknown"
            GroupId = ""
            GroupName = ""
            IncludeExclude = "Unknown"
            FilterId = ""
            FilterType = ""
        }
    }

    $odataType = [string](Get-PropertyIfExists -Item $target -PropertyName "@odata.type")
    $groupId = [string](Get-PropertyIfExists -Item $target -PropertyName "groupId")
    $filterId = [string](Get-PropertyIfExists -Item $target -PropertyName "deviceAndAppManagementAssignmentFilterId")
    $filterType = [string](Get-PropertyIfExists -Item $target -PropertyName "deviceAndAppManagementAssignmentFilterType")

    $includeExclude = if ($odataType.ToLowerInvariant().Contains("exclusion")) { "Exclude" } else { "Include" }
    $targetType = "Unknown"
    $targetValue = "Unknown"
    $groupName = ""

    switch -Regex ($odataType.ToLowerInvariant()) {
        "allusers" {
            $targetType = "AllUsers"
            $targetValue = "All Users"
            break
        }
        "alldevices" {
            $targetType = "AllDevices"
            $targetValue = "All Devices"
            break
        }
        "group" {
            $targetType = "Group"
            $targetValue = $groupId
            if (-not [string]::IsNullOrWhiteSpace($groupId)) {
                if (-not $GroupCache.ContainsKey($groupId)) {
                    $groupUri = "https://graph.microsoft.com/v1.0/groups/$groupId?`$select=id,displayName"
                    $groupResult = Invoke-GraphGet -Uri $groupUri -AllowNotFound
                    $resolvedGroupName = [string](Get-PropertyIfExists -Item $groupResult -PropertyName "displayName")
                    $GroupCache[$groupId] = if (-not [string]::IsNullOrWhiteSpace($resolvedGroupName)) { $resolvedGroupName } else { "" }
                }
                $groupName = [string]$GroupCache[$groupId]
            }
            break
        }
        default {
            $targetType = if ([string]::IsNullOrWhiteSpace($odataType)) { "Unknown" } else { $odataType }
            $targetValue = $targetType
            break
        }
    }

    return [pscustomobject]@{
        TargetType = $targetType
        TargetValue = $targetValue
        GroupId = $groupId
        GroupName = $groupName
        IncludeExclude = $includeExclude
        FilterId = $filterId
        FilterType = $filterType
    }
}

function Normalize-RelativePath {
    param([string]$Path)
    return ($Path -replace "\\", "/").TrimStart("/")
}

Write-Log -Message "Runbook started. Authenticating with managed identity."
Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
$context = Get-AzContext
$tenantId = $context.Tenant.Id

$catalog = $null
if (-not [string]::IsNullOrWhiteSpace($EndpointCatalogJson)) {
    $catalog = $EndpointCatalogJson | ConvertFrom-Json
    Write-Log -Message "Endpoint catalog loaded from parameter."
}
elseif (Test-Path -Path (Join-Path $PSScriptRoot "endpoint-catalog.json")) {
    $catalog = Get-Content -Path (Join-Path $PSScriptRoot "endpoint-catalog.json") -Raw | ConvertFrom-Json
    Write-Log -Message "Endpoint catalog loaded from local endpoint-catalog.json."
}
else {
    $catalog = Get-EmbeddedCatalog
    Write-Log -Message "Endpoint catalog loaded from embedded default catalog."
}

$runId = [guid]::NewGuid().ToString()
$startedUtc = (Get-Date).ToUniversalTime()
$datePath = "{0}/{1}/{2}" -f $startedUtc.ToString("yyyy"), $startedUtc.ToString("MM"), $startedUtc.ToString("dd")
$runFolder = "{0}-{1}" -f $startedUtc.ToString("yyyyMMddTHHmmssZ"), $runId

$rootPrefix = $ExportRootPath.Trim("/")
$relativeRoot = if ([string]::IsNullOrWhiteSpace($rootPrefix)) {
    "$datePath/$runFolder"
}
else {
    "$rootPrefix/$datePath/$runFolder"
}

$tempRoot = Join-Path $env:TEMP ("intune-policy-export-" + $runId)
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

$reportsFolder = Join-Path $tempRoot "Reports"
New-Item -Path $reportsFolder -ItemType Directory -Force | Out-Null

$groupCache = @{}
$exportRows = [System.Collections.Generic.List[object]]::new()
$assignmentRows = [System.Collections.Generic.List[object]]::new()
$summaryRows = [System.Collections.Generic.List[object]]::new()
$errorRows = [System.Collections.Generic.List[object]]::new()

$stats = [ordered]@{
    EndpointsTotal = 0
    EndpointsSuccess = 0
    EndpointsFailed = 0
    ItemsExported = 0
    AssignmentRows = 0
    Errors = 0
}

foreach ($endpoint in $catalog) {
    $stats.EndpointsTotal++
    $endpointName = "$($endpoint.area)/$($endpoint.subcategory)"
    $endpointStart = Get-Date
    $itemCount = 0
    $itemErrors = 0

    try {
        Write-Log -Message "Exporting endpoint: $endpointName ($($endpoint.path))"
        $items = Get-GraphCollection -ApiVersion $endpoint.apiVersion -Path $endpoint.path

        foreach ($item in $items) {
            try {
                $itemId = if ($null -ne (Get-PropertyIfExists -Item $item -PropertyName "id")) { [string]$item.id } else { [guid]::NewGuid().ToString() }
                $itemName = Resolve-ItemName -Item $item
                $safeName = Get-SafeName -Name $itemName
                $safeId = Get-SafeName -Name $itemId
                $platformFolder = Resolve-PlatformFolder -Area $endpoint.area -Item $item
                $settingCount = Get-SettingCount -Item $item

                $relativeFolder = Normalize-RelativePath -Path "$platformFolder/$($endpoint.area)/$($endpoint.subcategory)"
                $fullFolder = Join-Path $tempRoot ($relativeFolder -replace "/", [IO.Path]::DirectorySeparatorChar)
                New-Item -Path $fullFolder -ItemType Directory -Force | Out-Null

                $fileName = "$safeName--$safeId.json"
                $localFilePath = Join-Path $fullFolder $fileName
                $item | ConvertTo-Json -Depth 100 | Set-Content -Path $localFilePath -Encoding UTF8

                $relativeFilePath = Normalize-RelativePath -Path "$relativeFolder/$fileName"
                $blobPath = Normalize-RelativePath -Path "$relativeRoot/$relativeFilePath"

                $assignments = @()
                if (-not [string]::IsNullOrWhiteSpace([string]$endpoint.assignmentPathTemplate)) {
                    $assignmentPath = [string]$endpoint.assignmentPathTemplate
                    $assignmentPath = $assignmentPath.Replace("{id}", $itemId)
                    try {
                        $assignments = Get-GraphCollection -ApiVersion $endpoint.apiVersion -Path $assignmentPath -AllowNotFound
                    }
                    catch {
                        $itemErrors++
                        $stats.Errors++
                        $errorRows.Add([pscustomobject]@{
                                TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                                Level = "AssignmentError"
                                Endpoint = $endpointName
                                ObjectId = $itemId
                                ObjectName = $itemName
                                Uri = "https://graph.microsoft.com/$($endpoint.apiVersion)$assignmentPath"
                                Message = $_.Exception.Message
                            })
                    }
                }

                foreach ($assignment in $assignments) {
                    $target = Resolve-AssignmentTarget -Assignment $assignment -GroupCache $groupCache
                    $assignmentId = if ($null -ne (Get-PropertyIfExists -Item $assignment -PropertyName "id")) { [string]$assignment.id } else { "" }

                    $assignmentRows.Add([pscustomobject]@{
                            ExportTimestampUtc = $startedUtc.ToString("o")
                            RunId = $runId
                            Category = $endpoint.area
                            Subcategory = $endpoint.subcategory
                            ObjectName = $itemName
                            ObjectId = $itemId
                            AssignmentId = $assignmentId
                            TargetType = $target.TargetType
                            TargetValue = $target.TargetValue
                            GroupId = $target.GroupId
                            GroupName = $target.GroupName
                            IncludeExclude = $target.IncludeExclude
                            FilterId = $target.FilterId
                            FilterType = $target.FilterType
                        })
                }

                $exportRows.Add([pscustomobject]@{
                        ExportTimestampUtc = $startedUtc.ToString("o")
                        TenantId = $tenantId
                        RunId = $runId
                        Category = $endpoint.area
                        Subcategory = $endpoint.subcategory
                        PlatformFolder = $platformFolder
                        Name = $itemName
                        Id = $itemId
                        ApiVersion = $endpoint.apiVersion
                        EndpointPath = $endpoint.path
                        SettingCount = $settingCount
                        AssignmentCount = $assignments.Count
                        CreatedDateTime = [string](Get-PropertyIfExists -Item $item -PropertyName "createdDateTime")
                        LastModifiedDateTime = [string](Get-PropertyIfExists -Item $item -PropertyName "lastModifiedDateTime")
                        FilePath = $blobPath
                        Status = "Exported"
                        ErrorMessage = ""
                    })

                $itemCount++
                $stats.ItemsExported++
                $stats.AssignmentRows += $assignments.Count
            }
            catch {
                $itemErrors++
                $stats.Errors++
                $errorRows.Add([pscustomobject]@{
                        TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                        Level = "ItemError"
                        Endpoint = $endpointName
                        ObjectId = [string](Get-PropertyIfExists -Item $item -PropertyName "id")
                        ObjectName = [string](Resolve-ItemName -Item $item)
                        Uri = "https://graph.microsoft.com/$($endpoint.apiVersion)$($endpoint.path)"
                        Message = $_.Exception.Message
                    })
            }
        }

        $stats.EndpointsSuccess++
    }
    catch {
        $stats.EndpointsFailed++
        $stats.Errors++
        $errorRows.Add([pscustomobject]@{
                TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
                Level = "EndpointError"
                Endpoint = $endpointName
                ObjectId = ""
                ObjectName = ""
                Uri = "https://graph.microsoft.com/$($endpoint.apiVersion)$($endpoint.path)"
                Message = $_.Exception.Message
            })
    }

    $elapsed = [math]::Round(((Get-Date) - $endpointStart).TotalSeconds, 2)
    $summaryRows.Add([pscustomobject]@{
            ExportTimestampUtc = $startedUtc.ToString("o")
            RunId = $runId
            Category = $endpoint.area
            Subcategory = $endpoint.subcategory
            ApiVersion = $endpoint.apiVersion
            EndpointPath = $endpoint.path
            ExportedItemCount = $itemCount
            ItemErrors = $itemErrors
            DurationSeconds = $elapsed
            Status = if ($itemErrors -gt 0) { "Partial" } else { "Success" }
        })
}

$allPoliciesCsv = Join-Path $reportsFolder "All-Policies.csv"
$summaryCsv = Join-Path $reportsFolder "Export-Summary.csv"
$errorsCsv = Join-Path $reportsFolder "Export-Errors.csv"
$assignmentsCsv = Join-Path $reportsFolder "Assignments.csv"
$manifestJson = Join-Path $reportsFolder "manifest.json"

$exportRows | Export-Csv -Path $allPoliciesCsv -NoTypeInformation -Encoding UTF8
$summaryRows | Export-Csv -Path $summaryCsv -NoTypeInformation -Encoding UTF8
$errorRows | Export-Csv -Path $errorsCsv -NoTypeInformation -Encoding UTF8
$assignmentRows | Export-Csv -Path $assignmentsCsv -NoTypeInformation -Encoding UTF8

$finishedUtc = (Get-Date).ToUniversalTime()
$manifest = [pscustomobject]@{
    schemaVersion = "1.0"
    runId = $runId
    tenantId = $tenantId
    startedUtc = $startedUtc.ToString("o")
    finishedUtc = $finishedUtc.ToString("o")
    durationSeconds = [math]::Round(($finishedUtc - $startedUtc).TotalSeconds, 2)
    storageAccountName = $StorageAccountName
    storageContainerName = $StorageContainerName
    blobRoot = $relativeRoot
    endpointCatalogCount = $catalog.Count
    stats = $stats
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestJson -Encoding UTF8

Write-Log -Message "Uploading artifacts to Storage Account $StorageAccountName / container $StorageContainerName"
Import-Module Az.Storage -ErrorAction Stop

$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
$container = Get-AzStorageContainer -Context $storageContext -Name $StorageContainerName -ErrorAction SilentlyContinue
if ($null -eq $container) {
    New-AzStorageContainer -Context $storageContext -Name $StorageContainerName -Permission Off | Out-Null
}

$uploadedCount = 0
$localFiles = Get-ChildItem -Path $tempRoot -File -Recurse
foreach ($file in $localFiles) {
    $relativeLocal = Normalize-RelativePath -Path $file.FullName.Substring($tempRoot.Length)
    $blobName = Normalize-RelativePath -Path "$relativeRoot/$relativeLocal"

    Set-AzStorageBlobContent -Context $storageContext -Container $StorageContainerName -Blob $blobName -File $file.FullName -Force | Out-Null
    $uploadedCount++
}

$result = [pscustomobject]@{
    status = if ($stats.EndpointsFailed -gt 0) { "PartialSuccess" } else { "Success" }
    runId = $runId
    tenantId = $tenantId
    exportedItems = $stats.ItemsExported
    assignmentRows = $stats.AssignmentRows
    endpointFailures = $stats.EndpointsFailed
    errorCount = $stats.Errors
    uploadedFiles = $uploadedCount
    blobRoot = $relativeRoot
    storageAccountName = $StorageAccountName
    containerName = $StorageContainerName
}

Write-Log -Message "Export completed. Items: $($stats.ItemsExported), Errors: $($stats.Errors), UploadedFiles: $uploadedCount"
$result | ConvertTo-Json -Depth 6

try {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Log -Message "Temp cleanup failed: $($_.Exception.Message)" -Level "WARN"
}
