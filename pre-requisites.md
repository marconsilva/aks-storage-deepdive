## Pre-requisites for the AKS Storage Deep Dive Lab environment

```powershell
# create the lab variables
$SUBSCRIPTION_ID="" # Replace with your subscription id
$RESOURCE_GROUP="aksstoragelab"
$CLUSTER="aksstoragelab"
$LOCATION="westeurope"
$VAULT_NAME="aksstoragelabkv"
$EsanName   = "aksstoragelabsan"
$EsanVgName = "aksstoragelabsanvg"
$VolumeName = "aksstoragelabsanvol"

$CLUSTER_1="aksstoragelab-1"
$RESOURCE_GROUP_1="aksstoragelab-1"
$CLUSTER_2="aksstoragelab-2"
$RESOURCE_GROUP_2="aksstoragelab-2"
$BACK_VAULT_NAME="backup-vault"
$RESOURCE_GROUP_VAULT="rg-backup-vault"
$SA_NAME="storagelabaks1backup13"
$SA_RG="rg-backup-storage"
$BLOB_CONTAINER_NAME="aks-backup"
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
az aks create -n $CLUSTER -g $RESOURCE_GROUP --location $LOCATION --network-plugin azure --network-plugin-mode overlay --pod-cidr 192.168.0.0/16 --generate-ssh-keys
```


```powershell
# enable extensions and providers
az extension add --name aks-preview
az extension update --name aks-preview
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.NetworkFunction
az provider register --namespace Microsoft.ServiceNetworking
az provider register --namespace Microsoft.ContainerService --name "TrustedAccessPreview"
az extension add --upgrade --name k8s-extension
az provider register --namespace Microsoft.KubernetesConfiguration  --wait
az extension add --name elastic-san --allow-preview true
```
