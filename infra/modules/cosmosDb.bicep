@description('Name of the Cosmos DB Account.')
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

@description('Specifies whether network isolation is enabled. This will create a private endpoint for the Cosmos DB Account and link the private DNS zone.')
param networkIsolation bool = true

@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

@description('Optional. List of principal IDs for the custom read/write SQL role assignment.')
param sqlRoleAssignmentsPrincipalIds string [] = []

@description('Optional. List of Cosmos DB databases to deploy.')
param databases sqlDatabaseType[]?

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (networkIsolation) {
  name: 'private-dns-cosmosdb-deployment'
  params: {
    name: 'privatelink.documents.azure.com'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetworkResourceId
      }
    ]
    tags: tags
  }
}

var nameFormatted = toLower(name)

module cosmosDb 'br/public:avm/res/document-db/database-account:0.13.0' =  {
  name: take('${nameFormatted}-cosmosdb-deployment', 64)
  #disable-next-line no-unnecessary-dependson
  dependsOn: [privateDnsZone] // required due to optional flags that could change dependency
  params: {
    name: nameFormatted
    automaticFailover: true
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceResourceId
      }
    ]
    disableKeyBasedMetadataWriteAccess: true
    disableLocalAuth: true
    location: location
    minimumTlsVersion: 'Tls12'
    defaultConsistencyLevel: 'Session'
    networkRestrictions: {
      networkAclBypass: 'None'
      publicNetworkAccess: networkIsolation ? 'Disabled' : 'Enabled'
    }
    privateEndpoints: networkIsolation ? [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZone.outputs.resourceId
            }
          ]
        }
        service: 'Sql'
        subnetResourceId: virtualNetworkSubnetResourceId
      }
    ] : []
    sqlDatabases: databases
    roleAssignments: roleAssignments
    sqlRoleDefinitions: [
      {
        name: guid(resourceGroup().id, nameFormatted, 'custom-sql-role')
        roleType: 'CustomRole'
        roleName: 'Cosmos DB Data Reader Writer'
        dataAction:[
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
        ]
      }
    ]
    sqlRoleAssignmentsPrincipalIds: sqlRoleAssignmentsPrincipalIds
    tags: tags
  }
}

import { roleAssignmentType } from 'br/public:avm/utl/types/avm-common-types:0.5.1'
import { sqlDatabaseType } from 'customTypes.bicep'

output resourceId string = cosmosDb.outputs.resourceId
output cosmosDBname string = cosmosDb.outputs.name
