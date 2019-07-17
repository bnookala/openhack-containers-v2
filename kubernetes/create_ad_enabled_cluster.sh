#!/bin/bash

# name of the (new) k8s cluster
aksname="ohaks"
aksgroup="teamResources"

# create an application in AD called `ohaksServer`
serverApplicationId=$(az ad app create \
    --display-name "${aksname}Server" \
    --identifier-uris "https://${aksname}Server" \
    --query appId -o tsv)

az ad app update --id $serverApplicationId --set groupMembershipClaims=All

# Create a service principal for the server application
az ad sp create --id $serverApplicationId

# Reset and get the Service Principal Password
serverApplicationSecret=$(az ad sp credential reset \
    --name $serverApplicationId \
    --credential-description "AKSPassword" \
    --query password -o tsv)

# Lol who knows
# Apparently 00000003-0000-0000-c000-000000000000 is the Microsoft Graph API
# But where on earth do I find a list of api permissions and their UUIDs
az ad app permission add \
    --id $serverApplicationId \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope 06da0dbc-49e2-44d2-8312-53f166ab848a=Scope 7ab1d382-f21e-4acd-a863-ba3e13f7da61=Role

# grant the permissions assigned in the previous step for the server application
az ad app permission grant --id $serverApplicationId --api 00000003-0000-0000-c000-000000000000

# also need to add permissions for Azure AD application to request information that may otherwise require administrative consent
az ad app permission admin-consent --id  $serverApplicationId

# Create Client APplication
clientApplicationId=$(az ad app create \
    --display-name "${aksname}Client" \
    --native-app \
    --reply-urls "https://${aksname}Client" \
    --query appId -o tsv)

# Create a service principal for the application
az ad sp create --id $clientApplicationId

# oAuth2 ID for the server app to allow the authentication flow between the two app components
# This is probably a GUID that is returned
oAuthPermissionId=$(az ad app show --id $serverApplicationId --query "oauth2Permissions[0].id" -o tsv)

# Give the client application permission to the server "api" along with the permissions it
# requires
az ad app permission add --id $clientApplicationId --api $serverApplicationId --api-permissions $oAuthPermissionId=Scope

# Grant the permission - similar to Line 35
az ad app permission grant --id $clientApplicationId --api $serverApplicationId

# Get the tenant ID
tenantId=$(az account show --query tenantId -o tsv)

# Create the AKS resource
az aks create \
    --resource-group $aksgroup \
    --name $aksname \
    --generate-ssh-keys \
    --aad-server-app-id $serverApplicationId \
    --aad-server-app-secret $serverApplicationSecret \
    --aad-client-app-id $clientApplicationId \
    --aad-tenant-id $tenantId

# Get credentials for the cluster
az aks get-credentials --resource-group $aksgroup --name $aksname --admin
