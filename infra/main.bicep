targetScope = 'resourceGroup'

@description('Resource location')
param location string = resourceGroup().location

@description('Single base name used to derive all resource names, for example intunex => aa-intunex, sch-intunex-daily')
@minLength(3)
@maxLength(20)
param baseName string = 'intunex'

@description('Blob root path prefix')
@minLength(1)
param exportRootPath string = 'daily'

@description('Retention in days for lifecycle cleanup')
@minValue(30)
@maxValue(3650)
param retentionDays int = 365

@description('Daily schedule start time in UTC (must be in the future)')
param scheduleStartTime string = dateTimeAdd(utcNow(), 'P2D', 'yyyy-MM-ddT00:00:00Z')

var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var automationContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f353d9bd-d4a6-484e-a77a-8050b599b867')
var runbookContentBase64 = base64(loadTextContent('../runbook/Export-IntuneConfiguration.ps1'))
var publishRunbookScriptContent = loadTextContent('publish-runbook.ps1')
var publishRunbookScriptContentHash = base64(publishRunbookScriptContent)
var normalizedBaseName = toLower(replace(baseName, '_', '-'))
var storageAccountName = 'st${uniqueString(resourceGroup().id, normalizedBaseName)}'
var storageContainerName = '${normalizedBaseName}-exports'
var automationAccountName = 'aa-${normalizedBaseName}'
var runbookName = 'rb-${normalizedBaseName}-export'
var scheduleName = 'sch-${normalizedBaseName}-daily'
var jobScheduleName = guid(automationAccount.id, runbook.name, scheduleName)
var deploymentIdentityName = 'mi-${normalizedBaseName}-ds'
var publishRunbookScriptName = 'ds-${normalizedBaseName}-publish-runbook'

resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: deploymentIdentityName
  location: location
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource storageBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: 'default'
  parent: storageAccount
}

resource storageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: storageContainerName
  parent: storageBlobService
  properties: {
    publicAccess: 'None'
  }
}

resource storageLifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'deleteOldExports'
          type: 'Lifecycle'
          definition: {
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: retentionDays
                }
              }
            }
            filters: {
              blobTypes: [
                'blockBlob'
              ]
              prefixMatch: [
                exportRootPath
              ]
            }
          }
        }
      ]
    }
  }
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  name: runbookName
  parent: automationAccount
  location: location
  properties: {
    description: 'Exports Intune configuration to Storage Account as JSON and CSV reports.'
    logActivityTrace: 0
    logProgress: true
    logVerbose: true
    runbookType: 'PowerShell72'
    draft: {}
  }
}

resource automationRoleForDeploymentScript 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, deploymentIdentity.name, 'automationContributor')
  scope: automationAccount
  properties: {
    roleDefinitionId: automationContributorRoleId
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource publishRunbookScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: publishRunbookScriptName
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.5'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
    timeout: 'PT45M'
    forceUpdateTag: uniqueString(runbookContentBase64, publishRunbookScriptContentHash)
    environmentVariables: [
      {
        name: 'RG_NAME'
        value: resourceGroup().name
      }
      {
        name: 'AA_NAME'
        value: automationAccount.name
      }
      {
        name: 'RUNBOOK_NAME'
        value: runbook.name
      }
      {
        name: 'AUTOMATION_API_VERSION'
        value: '2024-10-23'
      }
      {
        name: 'RUNBOOK_CONTENT_B64'
        value: runbookContentBase64
      }
    ]
    scriptContent: publishRunbookScriptContent
  }
  dependsOn: [
    automationRoleForDeploymentScript
  ]
}

resource storageRoleForAutomation 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, automationAccount.name, 'storageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource dailySchedule 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = {
  name: scheduleName
  parent: automationAccount
  properties: {
    description: 'Daily Intune policy export at 00:00 UTC'
    startTime: scheduleStartTime
    frequency: 'Day'
    interval: 1
    timeZone: 'Etc/UTC'
  }
}

resource dailyJobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2024-10-23' = {
  name: jobScheduleName
  parent: automationAccount
  properties: {
    schedule: {
      name: dailySchedule.name
    }
    runbook: {
      name: runbook.name
    }
    parameters: {
      StorageAccountName: storageAccount.name
      StorageContainerName: storageContainerName
      ExportRootPath: exportRootPath
    }
  }
  dependsOn: [
    publishRunbookScript
    storageRoleForAutomation
  ]
}

output storageAccountResourceId string = storageAccount.id
output storageAccountNameOut string = storageAccount.name
output storageContainer string = storageContainerName
output automationAccountResourceId string = automationAccount.id
output automationAccountNameOut string = automationAccount.name
output automationPrincipalId string = automationAccount.identity.principalId
output runbookNameOut string = runbook.name
output scheduleResourceId string = dailySchedule.id
output scheduleNameOut string = dailySchedule.name
output jobScheduleResourceId string = dailyJobSchedule.id
