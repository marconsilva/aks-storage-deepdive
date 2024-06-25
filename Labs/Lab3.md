## Lab 3: Provision/enable Azure Container Storage in an AKS Cluster and Stress Testing

In this lab, you will learn how to provision and enable Azure Container Storage in an Azure Kubernetes Service (AKS) cluster. You will also do some stress testing to see how the storage behaves under load.

Azure Container Storage is a cloud-based volume management, deployment, and orchestration service built natively for containers. This article shows you how to configure Azure Container Storage to use Azure managed disks as back-end storage for your Kubernetes workloads. At the end, you'll have a pod that's using Azure managed disks as its storage.

### 1. Install Azure Container Storage Preview for use with Azure Kubernetes Service

#### 1.1 Assign Azure Container Storage Operator role to AKS managed identity
You only need to perform this step if you plan to use Azure Elastic SAN as backing storage. In order to use Elastic SAN, you'll need to grant permissions to allow Azure Container Storage to provision storage for your cluster. Specifically, you must assign the Azure Container Storage Operator role to the AKS managed identity. You can do this using the Azure portal or Azure CLI. You'll need either an Azure Container Storage Owner role or Azure Container Storage Contributor role for your Azure subscription in order to do this. If you don't have sufficient permissions, ask your admin to perform these steps.

```powershell
$AKS_MI_OBJECT_ID=$(az aks show --name $CLUSTER --resource-group $RESOURCE_GROUP --query "identityProfile.kubeletidentity.objectId" -o tsv)
az role assignment create --assignee $AKS_MI_OBJECT_ID --role "Azure Container Storage Operator" --scope "/subscriptions/$SUBSCRIPTION_ID"
```

#### 1.2 Install Azure Container Storage

The initial install uses Azure Arc CLI commands to download a new extension.

```powershell
az k8s-extension create --cluster-type managedClusters --cluster-name $CLUSTER --resource-group $RESOURCE_GROUP --name "aksstoragelab" --extension-type microsoft.azurecontainerstorage --scope cluster --release-train stable --release-namespace acstor
```

Installation takes 10-15 minutes to complete. You can check if the installation completed correctly by running the following command and ensuring that provisioningState says **Succeeded**:

```powershell
az k8s-extension list --cluster-name $CLUSTER --resource-group $RESOURCE_GROUP --cluster-type managedClusters
```

Congratulations, you've successfully installed Azure Container Storage. You now have new storage classes that you can use for your Kubernetes workloads.

### 2. Use Azure Container Storage Preview with Azure managed disks

First, create a storage pool, which is a logical grouping of storage for your Kubernetes cluster, by defining it in a YAML manifest file.

You have the following options for creating a storage pool:

- Create a dynamic storage pool
- Create a pre-provisioned storage pool using pre-provisioned Azure managed disks
- Create a dynamic storage pool using your own encryption key (optional)

we will be using a Dynamic storage pool for this lab.

first lets create a storage pool

```powershell
kubectl create namespace acstor

kubectl apply -f acstor-storagepool.yaml
```




### 3. Use Azure Container Storage Preview with Azure Elastic SAN
