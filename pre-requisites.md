## Pre-requisites for the AKS Storage Deep Dive Lab environment

```powershell
# create the lab variables
$SUBSCRIPTION_ID="" # Replace with your subscription id
$RESOURCE_GROUP="aksstoragelab"
$CLUSTER="aksstoragelab"
$LOCATION="westeurope"
$VAULT_NAME="aksstoragelabkv"
$EsanName = "aksstoragelabsan"
$EsanVgName = "aksstoragelabsanvg"
$VolumeName = "aksstoragelabsanvol"
```

```powershell
# create the resource group
az login
az account set --subscription $SUBSCRIPTION_ID
```

```powershell
# create the resource group
az group create -n $RESOURCE_GROUP -l $LOCATION
```

```powershell
# create the keyvault
az keyvault create -n $VAULT_NAME -g $RESOURCE_GROUP -l $LOCATION
```

```powershell
# create an AKS with Azure CNI Overlay Network Plugin
az aks create -n $CLUSTER -g $RESOURCE_GROUP --location $LOCATION --network-plugin azure --network-plugin-mode overlay --pod-cidr 192.168.0.0/16 --generate-ssh-keys --node-vm-size Standard_DS4_v2 --node-count 3
```


```powershell
# enable extensions and providers
az extension add --name aks-preview
az extension update --name aks-preview
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.NetworkFunction
az provider register --namespace Microsoft.ServiceNetworking
az provider register --namespace Microsoft.ContainerService
az extension add --upgrade --name k8s-extension
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration
az provider register --namespace Microsoft.ExtendedLocation
az extension add --name elastic-san --allow-preview true
az provider register --namespace Microsoft.NetApp
```
