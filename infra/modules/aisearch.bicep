@description('Name of the AI Search resource.')
param name string

@description('Specifies the location for all the Azure resources.')
param location string

@description('Optional. Tags to be applied to the resources.')
param tags object = {}

@description('Resource ID of the virtual network to link the private DNS zones.')
param virtualNetworkResourceId string

@description('Resource ID of the subnet for the private endpoint.')
param virtualNetworkSubnetResourceId string

@description('Resource ID of the Log Analytics workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceResourceId string

@description('Specifies whether network isolation is enabled. This will create a private endpoint for the AI Search resource and link the private DNS zone.')
param networkIsolation bool

import { roleAssignmentType } from 'br/public:avm/utl/types/avm-common-types:0.5.1'
@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (networkIsolation)  {
  name: 'private-dns-search-deployment'
  params: {
    name: 'privatelink.search.windows.net'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

var nameFormatted = take(toLower(name), 60)

module aiSearch 'br/public:avm/res/search/search-service:0.10.0' = {
  name: take('${nameFormatted}-search-services-deployment', 64)
  // Ensure dependency on private DNS zone only when network isolation is enabled
  dependsOn: networkIsolation ? [ privateDnsZone ] : []
  params: {
      name: nameFormatted
      location: location
      cmkEnforcement: 'Disabled'
      managedIdentities: {
        systemAssigned: true
      }
      publicNetworkAccess: networkIsolation ? 'Disabled' : 'Enabled'
      networkRuleSet: {
        bypass: 'AzureServices'
      }
      disableLocalAuth: true
      sku: 'standard'
      partitionCount: 1
      replicaCount: 3
      roleAssignments: roleAssignments
      diagnosticSettings: [
        {
          workspaceResourceId: logAnalyticsWorkspaceResourceId
        }
      ]
      privateEndpoints: networkIsolation ? [
        {
          privateDnsZoneGroup: {
            privateDnsZoneGroupConfigs: [
              {
                // Non-null assertion since this module only exists when networkIsolation is true
                privateDnsZoneResourceId: privateDnsZone!.outputs.resourceId
              }
            ]
          }
          subnetResourceId: virtualNetworkSubnetResourceId
        }
      ] : []
      tags: tags
  }
}



output resourceId string = aiSearch.outputs.resourceId
output name string = aiSearch.outputs.name
output systemAssignedMIPrincipalId string = aiSearch.outputs.?systemAssignedMIPrincipalId ?? ''

