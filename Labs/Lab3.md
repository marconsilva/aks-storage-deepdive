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
az k8s-extension create --cluster-type managedClusters --cluster-name $CLUSTER --resource-group $RESOURCE_GROUP --name "azurecontainerstorage" --extension-type microsoft.azurecontainerstorage --scope cluster --release-train stable --release-namespace acstor
```

Installation takes 10-15 minutes to complete. You can check if the installation completed correctly by running the following command and ensuring that provisioningState says **Succeeded**:

```powershell
az k8s-extension list --cluster-name $CLUSTER --resource-group $RESOURCE_GROUP --cluster-type managedClusters
```
We need to add the **acstor.azure.com/io-engine:acstor** lable to the **nodepool1** nodepool, so the Azure Container Storage can use it as a storage pool.

```powershell
kubectl label node -n acstor --overwrite nodepool1 acstor.azure.com/io-engine=acstor
```

Congratulations, you've successfully installed Azure Container Storage. You now have new storage classes that you can use for your Kubernetes workloads.

### 2. Use Azure Container Storage Preview with Azure managed disks

First, create a storage pool, which is a logical grouping of storage for your Kubernetes cluster, by defining it in a YAML manifest file.

You have the following options for creating a storage pool:

- Create a dynamic storage pool
- Create a pre-provisioned storage pool using pre-provisioned Azure managed disks
- Create a dynamic storage pool using your own encryption key (optional)

we will be using a Dynamic storage pool for this lab.

First lets create a storage pool

```powershell
kubectl apply -f acstor-storagepool.yaml
```

Lets see the storage pool we just created

```powershell
kubectl describe sp azuredisk -n acstor
```

When the storage pool is created, Azure Container Storage will create a storage class on your behalf, using the naming convention acstor-<storage-pool-name>. Now we can display the available storage classes and create a persistent volume claim.

To display the available storage classes, run the following command:

```powershell
kubectl get sc 
```

### 2.1 Create a persistent volume claim

Now that we created the storage pool, and storage class, we can create a persistent volume claim (PVC) to use the storage class. 

Lest your the following command to create the PVC:

```powershell
kubectl apply -f acstor-pvc.yaml
```
You can verify the status of the PVC by running the following command:

```powershell
kubectl describe pvc azurediskpvc
```

### 2.2 Deploy a pod and attach a persistent volume to it

Lets create a pod using Fio (Flexible I/O Tester) for benchmarking and workload simulation, and specify a mount path for the persistent volume.

To to this, run the following command:

```powershell
kubectl apply -f acstor-pod.yaml
```

Check that the pod is running and that the persistent volume claim has been bound successfully to the pod:

```powershell
kubectl describe pod fiopod
kubectl describe pvc azurediskpvc
```

Now lets make some load on the storage to see how it behaves under load.

```powershell
kubectl exec -it fiopod -- fio --name=benchtest --size=800m --filename=/volume/test --direct=1 --rw=randrw --ioengine=libaio --bs=4k --iodepth=16 --numjobs=8 --time_based --runtime=60
```

### 3. Use Azure Container Storage Preview with Azure Elastic SAN
This Lab will now shows you how to configure Azure Container Storage to use Azure Elastic SAN as back-end storage for your Kubernetes workloads. At the end, you'll have a pod that's using Elastic SAN as its storage.

First, create a storage pool, which is a logical grouping of storage for your Kubernetes cluster, run this to create a storage pool:

```powershell
kubectl apply -f acstor-storagepool-elastic-san.yaml
```

You can also run this command to check the status of the storage pool

```powershell
kubectl describe sp managed -n acstor
```

When the storage pool is created, Azure Container Storage will create a storage class on your behalf using the naming convention acstor-<storage-pool-name>. **It will also create an Azure Elastic SAN resource**.

You can also check the created StorageClass by running this command and you should find the **acstor-managed** SC with the provider **san.csi.azure.com**:

```powershell
kubectl get sc 
```

### 3.1 Create a persistent volume claim
Now we can create a persistent volume claim (PVC) to use the storage class.

```powershell
kubectl apply -f acstor-pvc-elastic-san.yaml
```

You can verify the status of the PVC by running the following command:

```powershell	
kubectl describe pvc managedpvc
```
Once the PVC is created, it's ready for use by a pod.
Lets do the same as we did with the Azure managed disks, create a pod using Fio (Flexible I/O Tester) for benchmarking and workload simulation, and specify a mount path for the persistent volume.

```powershell
kubectl apply -f acstor-pod-elastic-san.yaml
```

Check that the pod is running and that the persistent volume claim has been bound successfully to the pod:

```powershell
kubectl describe pod fiopod
kubectl describe pvc managedpvc
```

Now lets make some load on the storage again and see how it behaves.

```powershell
kubectl exec -it fiopod -- fio --name=benchtest --size=800m --filename=/volume/test --direct=1 --rw=randrw --ioengine=libaio --bs=4k --iodepth=16 --numjobs=8 --time_based --runtime=60
```