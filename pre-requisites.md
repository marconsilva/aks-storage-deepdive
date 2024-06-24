## Pre-requisites for the AKS Storage Deep Dive Lab environment

```bash
# create the lab variables
export SUBSCRIPTION_ID=""
export RESOURCE_GROUP=aksstoragelab
export CLUSTER=aksstoragelab
export LOCATION=westeurope
export VAULT_NAME=aksstoragelabkv
```


```bash
# create the resource group
az group create -n $RESOURCE_GROUP -l $LOCATION
```

```bash
# create the keyvault
az keyvault create -n $VAULT_NAME -g $RESOURCE_GROUP -l $LOCATION
```

```bash
# create an AKS with Azure CNI Overlay Network Plugin

az aks create -n $CLUSTER -g $RESOURCE_GROUP --location $LOCATION --network-plugin azure --network-plugin-mode overlay --pod-cidr 192.168.0.0/16
```


```bash
# enable extensions and providers
az extension add --name aks-preview
az extension update --name aks-preview
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.NetworkFunction
az provider register --namespace Microsoft.ServiceNetworking
az provider register --namespace Microsoft.ContainerService
```
