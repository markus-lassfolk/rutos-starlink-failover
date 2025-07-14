// Bicep template to deploy a serverless logging solution for RUTOS devices.
// This creates a Storage Account, a Consumption Plan, and a Function App.

// PARAMETERS: User-configurable values
@description('The unique prefix for all created resources. Default is "rutos".')
param prefix string = 'rutos'

@description('The Azure region where resources will be deployed. Default is "westeurope".')
param location string = 'westeurope'

// VARIABLES: Internal names for resources
var storageAccountName = '${prefix}logstorage${uniqueString(resourceGroup().id)}'
var functionAppName = '${prefix}-log-ingestor-${uniqueString(resourceGroup().id)}'
var appServicePlanName = '${prefix}-log-plan'
var applicationInsightsName = '${prefix}-log-insights'

// RESOURCE: Application Insights for monitoring the Function App
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    IngestionMode: 'ApplicationInsights'
  }
}

// RESOURCE: Storage Account to hold the logs and Function App data
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS' // Use locally redundant storage for lowest cost
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// RESOURCE: App Service Plan (Consumption Tier Y1) for serverless execution
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1' // This is the dynamic "Consumption" plan tier
    tier: 'Dynamic'
  }
  properties: {}
}

// RESOURCE: The Function App itself
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned' // Give the function an identity to access storage
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https,AccountName=${storageAccountName},EndpointSuffix=${environment().suffixes.storage},AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell' // Set the language runtime
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

// Grant the Function App's identity the "Storage Blob Data Contributor" role
// This allows it to write to the blob container without needing keys in the code.
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount // Scope the role to the storage account
  name: guid(resourceGroup().id, functionApp.id, 'StorageBlobDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e78b22c70ae1') // Static ID for "Storage Blob Data Contributor"
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// OUTPUTS: Information you will need after deployment
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://' + functionApp.properties.defaultHostName
