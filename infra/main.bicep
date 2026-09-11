targetScope = 'resourceGroup'

@description('Resource location')
param location string = resourceGroup().location

@description('Single base name used to derive all resource names, for example intunex => la-intunex, aa-intunex')
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

var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var automationJobOperatorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4fe576fe-1146-4730-92eb-48519fa6bf9f')
var automationContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f353d9bd-d4a6-484e-a77a-8050b599b867')
var logicDefinition = loadJsonContent('workflow-definition.json')
var runbookContentBase64 = base64(loadTextContent('../runbook/Export-IntuneConfiguration.ps1'))
var publishRunbookScriptContent = loadTextContent('publish-runbook.ps1')
var normalizedBaseName = toLower(replace(baseName, '_', '-'))
var storageAccountName = 'st${uniqueString(resourceGroup().id, normalizedBaseName)}'
var storageContainerName = '${normalizedBaseName}-exports'
var automationAccountName = 'aa-${normalizedBaseName}'
var logicAppName = 'la-${normalizedBaseName}'
var runbookName = 'rb-${normalizedBaseName}-export'
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
    forceUpdateTag: uniqueString(runbookContentBase64)
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

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: logicDefinition
    parameters: {
      automationApiVersion: {
        value: '2024-10-23'
      }
      subscriptionId: {
        value: subscription().subscriptionId
      }
      resourceGroupName: {
        value: resourceGroup().name
      }
      automationAccountName: {
        value: automationAccount.name
      }
      runbookName: {
        value: runbook.name
      }
      storageAccountName: {
        value: storageAccount.name
      }
      storageContainerName: {
        value: storageContainerName
      }
      exportRootPath: {
        value: exportRootPath
      }
    }
  }
  dependsOn: [
    publishRunbookScript
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

resource automationRoleForLogicApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, logicApp.name, 'automationJobOperator')
  scope: automationAccount
  properties: {
    roleDefinitionId: automationJobOperatorRoleId
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output storageAccountResourceId string = storageAccount.id
output storageAccountNameOut string = storageAccount.name
output storageContainer string = storageContainerName
output automationAccountResourceId string = automationAccount.id
output automationAccountNameOut string = automationAccount.name
output automationPrincipalId string = automationAccount.identity.principalId
output runbookNameOut string = runbook.name
output logicAppResourceId string = logicApp.id
output logicAppNameOut string = logicApp.name
output logicAppPrincipalId string = logicApp.identity.principalId
