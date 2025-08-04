@description('The name of the API Management service.')
param name string

@description('The location of the API Management service.')
param location string

@description('Name of the API Management publisher.')
param publisherName string

@description('The email address of the API Management publisher.')
param publisherEmail string

@description('The XML content for the API policy')
param policyXml string

@description('Optional. The pricing tier of this API Management service.')
@allowed([
  'Consumption'
  'Developer'
  'Basic'
  'Standard'
  'Premium'
  'StandardV2'
  'BasicV2'
])
param sku string

@description('Specifies whether to create a private endpoint for the API Management service.')
param networkIsolation bool

@description('The resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Resource ID of the virtual network to link the private DNS zones.')
param virtualNetworkResourceId string

@description('Resource ID of the subnet for the private endpoint.')
param virtualNetworkSubnetResourceId string

@description('Optional tags to be applied to the resources.')
param tags object = {}

@description('Required. The backend URL for the AI Foundry API.')
param foundryBackendUrl string

@description('The inference API type')
@allowed([
  'AzureOpenAI'
  'AzureAI'
  'OpenAI'
])
param inferenceAPIType string = 'AzureOpenAI'

@description('The name of the Inference backend pool.')
param inferenceBackendPoolName string = 'ai-foundry-backend'

var updatedPolicyXml = replace(policyXml, '{backend-id}', inferenceBackendPoolName)

var endpointPath = (inferenceAPIType == 'AzureOpenAI') ? 'openai' : (inferenceAPIType == 'AzureAI') ? 'models' : ''

module apiManagementService 'br/public:avm/res/api-management/service:0.9.1' = {
  name: take('${name}-apim-deployment', 64)
  params: {
    name: name
    location: location
    tags: tags
    sku: sku
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: networkIsolation ? 'Internal' : 'None'
    managedIdentities: {
      systemAssigned: true
    }
    apis: [
      {
        apiVersionSet: {
          name: 'ai-foundry-version-set'
          properties: {
            description: 'An AI Foundry API version set'
            displayName: 'AI Foundry version set'
            versioningScheme: 'Segment'
          }
        }
        description: 'An AI Foundry API service'
        displayName: 'AI Foundry API'
        name: 'ai-foundry-api'
        path: 'ai-foundry/${endpointPath}'
        protocols: [
          'https'
        ]
        policies: [
          {
            format: 'rawxml'
            value: updatedPolicyXml
          }
        ]
        value: string((inferenceAPIType == 'AzureOpenAI') ? loadJsonContent('./specs/AIFoundryOpenAI.json') : (inferenceAPIType == 'AzureAI') ? loadJsonContent('./specs/AIFoundryAzureAI.json') : (inferenceAPIType == 'OpenAI') ? loadJsonContent('./specs/AIFoundryAzureAI.json') : loadJsonContent('./specs/PassThrough.json')) 
        serviceUrl: 'https://ai.azure.com/'
      }
    ]
    backends: [
      {
        name: inferenceBackendPoolName
        description: 'AI Foundry backend service'
        url: '${foundryBackendUrl}/${endpointPath}'
      }
    ]
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'True'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
    }
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceResourceId
      }
    ]
    products: [
      {
        apis: [
          {
            name: 'ai-foundry-api'
          }
        ]
        approvalRequired: true
        description: 'This is an AI Foundry API'
        displayName: 'AI Foundry API'
        groups: [
          {
            name: 'developers'
          }
        ]
        name: 'Starter'
        subscriptionRequired: true
        terms: 'By accessing or using the services provided by Echo API through Azure API Management, you agree to be bound by these Terms of Use. These terms may be updated from time to time, and your continued use of the services constitutes acceptance of any changes.'
      }
    ]
    subscriptions: [
      {
        displayName: 'testArmSubscriptionAllApis'
        name: 'testArmSubscriptionAllApis'
        scope: '/apis'
      }
    ]
  }
}


module apiManagementPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (networkIsolation)  {
  name: 'private-dns-apim-deployment'
  params: {
    name: 'privatelink.apim.windows.net'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}


module apimPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.0' = if (networkIsolation) {
  name: take('${name}-apim-private-endpoint-deployment', 64)
  params: {
    name: toLower('pep-${apiManagementService.outputs.name}')
    subnetResourceId: virtualNetworkSubnetResourceId
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: apiManagementPrivateDnsZone!.outputs.resourceId
        }
      ]
    }
    privateLinkServiceConnections: [
      {
        name: apiManagementService.outputs.name
        properties: {
          groupIds: [
            'Gateway'
          ]
          privateLinkServiceId: apiManagementService.outputs.resourceId
        }
      }
    ]
  }
}

output resourceId string = apiManagementService.outputs.resourceId
output name string = apiManagementService.outputs.name
// Provide private endpoint outputs when created
// Only output private endpoint information when network isolation is enabled
output privateEndpointId string = networkIsolation ? apimPrivateEndpoint!.outputs.resourceId : ''
output privateEndpointName string = networkIsolation ? apimPrivateEndpoint!.outputs.name : ''
output principalId string? = apiManagementService.outputs.?systemAssignedMIPrincipalId


