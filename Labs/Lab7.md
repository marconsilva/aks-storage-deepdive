
## Lab 7: Configure Backup on a cluster and how to use Resource Modification to patch backed-up

Azure Kubernetes Service (AKS) backup is a simple, cloud-native process you can use to back up and restore containerized applications and data that run in your AKS cluster. You can configure scheduled backups for cluster state and application data that's stored on persistent volumes in CSI driver-based Azure Disk Storage. The solution gives you granular control to choose a specific namespace or an entire cluster to back up or restore by storing backups locally in a blob container and as disk snapshots. You can use AKS backup for end-to-end scenarios, including operational recovery, cloning developer/test environments, and cluster upgrade scenarios.

Use AKS backup to back up your AKS workloads and persistent volumes that are deployed in AKS clusters. The solution requires the Backup extension to be installed inside the AKS cluster. The Backup vault communicates to the extension to complete operations that are related to backup and restore. Using the Backup extension is mandatory, and the extension must be installed inside the AKS cluster to enable backup and restore for the cluster. When you configure AKS backup, you add values for a storage account and a blob container where backups are stored.

Lets start by creating a new resource group and a new backup vault to store the backups.

```powershell
az group create --name $RESOURCE_GROUP_VAULT --location $LOCATION

az dataprotection backup-vault create `
   --vault-name $BACK_VAULT_NAME `
   -g $RESOURCE_GROUP_VAULT `
   --storage-setting "[{type:'LocallyRedundant',datastore-type:'VaultStore'}]"
```

Lets create the blob storage account and the container to store the backups.

```powershell
az group create --name $SA_RG --location westeurope

az storage account create `
   --name $SA_NAME `
   --resource-group $SA_RG `
   --sku Standard_LRS

$ACCOUNT_KEY=$(az storage account keys list --account-name $SA_NAME -g $SA_RG --query "[0].value" -o tsv)

az storage container create `
   --name $BLOB_CONTAINER_NAME `
   --account-name $SA_NAME `
   --account-key $ACCOUNT_KEY
```

Now lets create first AKS cluster with CSI Disk Driver and Snapshot Controller

```powershell
az aks get-versions -l westeurope -o table

az group create --name $RESOURCE_GROUP_1 --location westeurope

az aks create -g $RESOURCE_GROUP_1 -n $CLUSTER_1 -k "1.27.3" --zones 1 2 3 --node-vm-size "Standard_B2als_v2"
```

We just need now to verify that CSI Disk Driver and Snapshot Controller are installed

```powershell
az aks show -g $RESOURCE_GROUP_1 -n $CLUSTER_1 --query storageProfile
```

If not installed, you can install them using the following command

```powershell
az aks update -g $RESOURCE_GROUP_1 -n $CLUSTER_1 --enable-disk-driver --enable-snapshot-controller
```

Lets now create a second AKS cluster with CSI Disk Driver and Snapshot Controller and verify that they are installed

```powershell
az group create --name $RESOURCE_GROUP_2 --location westeurope

az aks create -g $RESOURCE_GROUP_2 -n $CLUSTER_2 -k "1.27.3" --zones 1 2 3 --node-vm-size "Standard_B2als_v2"

# Verify that CSI Disk Driver and Snapshot Controller are installed

az aks show -g $RESOURCE_GROUP_2 -n $CLUSTER_2 --query storageProfile
```

If not installed, you ca install it with this command:

```powershell
az aks update -g $RESOURCE_GROUP_2 -n $CLUSTER_2 --enable-disk-driver --enable-snapshot-controller
```

We can now prepare the backup extension and install it in the first AKS cluster

```powershell
az k8s-extension create --name azure-aks-backup `
   --extension-type Microsoft.DataProtection.Kubernetes `
   --scope cluster `
   --cluster-type managedClusters `
   --cluster-name $CLUSTER_1 `
   --resource-group $RESOURCE_GROUP_1 `
   --release-train stable `
   --configuration-settings `
   blobContainer=$BLOB_CONTAINER_NAME `
   storageAccount=$SA_NAME `
   storageAccountResourceGroup=$SA_RG `
   storageAccountSubscriptionId=$SUBSCRIPTION_ID

# View Backup Extension installation status

az k8s-extension show --name azure-aks-backup --cluster-type managedClusters --cluster-name $CLUSTER_1 -g $RESOURCE_GROUP
```

We now need to Enable Trusted Access in AKS cluster to allow the backup extension to access the storage account

```powershell
$BACKUP_VAULT_ID=$(az dataprotection backup-vault show --vault-name $BACK_VAULT_NAME -g $RESOURCE_GROUP_VAULT --query id -o tsv)

az aks trustedaccess rolebinding create –n trustedaccess `
   -g $RESOURCE_GROUP_1 `
   --cluster-name $CLUSTER_1 `
   --source-resource-id $BACKUP_VAULT_ID `
   --roles Microsoft.DataProtection/backupVaults/backup-operator

az aks trustedaccess rolebinding list -g $RESOURCE_GROUP_1 --cluster-name $CLUSTER
```

We need to do the same for the second AKS cluster

```powershell

az k8s-extension create --name azure-aks-backup `
   --extension-type Microsoft.DataProtection.Kubernetes `
   --scope cluster `
   --cluster-type managedClusters `
   --cluster-name $CLUSTER_2 `
   --resource-group $RESOURCE_GROUP_2 `
   --release-train stable `
   --configuration-settings `
   blobContainer=$BLOB_CONTAINER_NAME `
   storageAccount=$SA_NAME `
   storageAccountResourceGroup=$SA_RG `
   storageAccountSubscriptionId=$SUBSCRIPTION_ID

# View Backup Extension installation status

az k8s-extension show --name azure-aks-backup --cluster-type managedClusters --cluster-name $CLUSTER_2 -g $RESOURCE_GROUP_2

# Enable Trusted Access in AKS

$BACKUP_VAULT_ID=$(az dataprotection backup-vault show --vault-name $BACK_VAULT_NAME -g $RESOURCE_GROUP_VAULT --query id -o tsv)

az aks trustedaccess rolebinding create `
   -g $RESOURCE_GROUP_2 `
   --cluster-name $CLUSTER_2 `
   –n trustedaccess `
   -s $BACKUP_VAULT_ID `
   --roles Microsoft.DataProtection/backupVaults/backup-operator
```

We can now create the backup policy and backup instance

```powershell
az dataprotection backup-instance create -g MyResourceGroup --vault-name MyVault --backup-instance backupinstance.json

az backup container register --resource-group $RESOURCE_GROUP_1 --vault-name $BACK_VAULT_NAME --subscription $SUBSCRIPTION_ID --backup-management-type AzureKubernetesService --workload-type AzureKubernetesService --query properties.friendlyName -o tsv

$CONTAINER_NAME=$(az backup container list --resource-group $RESOURCE_GROUP_1 --vault-name $BACK_VAULT_NAME --subscription $SUBSCRIPTION_ID --backup-management-type AzureKubernetesService --query "[0].name" -o tsv)

az backup item set-policy --resource-group $RESOURCE_GROUP_1 --vault-name $BACK_VAULT_NAME --subscription $SUBSCRIPTION_ID --container-name $CONTAINER_NAME --item-name $CONTAINER_NAME --policy-name "aks-backup-policy"
```

Finally we can create a backup job for each cluster

```powershell
az backup job start --resource-group $RESOURCE_GROUP_1 --vault-name $BACK_VAULT_NAME --subscription $SUBSCRIPTION_ID --container-name $CONTAINER_NAME --item-name $CONTAINER_NAME --backup-management-type AzureKubernetesService --workload-type AzureKubernetesService --operation TriggerBackup

az backup job start --resource-group $RESOURCE_GROUP_2 --vault-name $BACK_VAULT_NAME --subscription $SUBSCRIPTION_ID --container-name $CONTAINER_NAME --item-name $CONTAINER_NAME --backup-management-type AzureKubernetesService --workload-type AzureKubernetesService --operation TriggerBackup
```

Now lets check the status of the backup jobs

```powershell
az aks get-credentials -n $CLUSTER_1 -g $RESOURCE_GROUP_1 --overwrite-existing
kubectl get pods -n dataprotection-microsoft
```

You should see something like this

```output
# NAME                                                         READY   STATUS    RESTARTS      AGE
# dataprotection-microsoft-controller-7b8977698c-v2rl7         2/2     Running   0             94m
# dataprotection-microsoft-geneva-service-6c8457bbd-jgw49      2/2     Running   0             94m
# dataprotection-microsoft-kubernetes-agent-5558dbbf8f-5tdkc   2/2     Running   2 (94m ago)   94m
```


```powershell
kubectl get nodes
```

```output
# NAME                                 STATUS   ROLES   AGE   VERSION
# aks-systempool-20780455-vmss000000   Ready    agent   28m   v1.25.5
# aks-systempool-20780455-vmss000001   Ready    agent   28m   v1.25.5
# aks-systempool-20780455-vmss000002   Ready    agent   28m   v1.25.5
```

```powershell
kubectl apply -f deploy_disk_lrs.yaml
```

```powershell
kubectl apply -f deploy_disk_zrs_sc.yaml
```

```powershell
kubectl get pods,svc,pv,pvc
```
```output
# NAME                             READY   STATUS    RESTARTS   AGE
# pod/nginx-lrs-7db4886f8c-x4hzz   1/1     Running   0          90s
# pod/nginx-zrs-5567fd9ddc-hbtfs   1/1     Running   0          80s

# NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
# service/kubernetes   ClusterIP   10.0.0.1     <none>        443/TCP   30m

# NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                            STORAGECLASS      REASON   AGE
# persistentvolume/pvc-c3fc20ea-2922-477c-a337-895b8b503a9b   5Gi        RWO            Delete           Bound    default/azure-managed-disk-lrs   managed-csi                86s
# persistentvolume/pvc-f1055e1c-b8e1-4604-8567-1f288daced02   5Gi        RWO            Delete           Bound    default/azure-managed-disk-zrs   managed-csi-zrs            76s

# NAME                                           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      AGE
# persistentvolumeclaim/azure-managed-disk-lrs   Bound    pvc-c3fc20ea-2922-477c-a337-895b8b503a9b   5Gi        RWO            managed-csi       90s
# persistentvolumeclaim/azure-managed-disk-zrs   Bound    pvc-f1055e1c-b8e1-4604-8567-1f288daced02   5Gi        RWO            managed-csi-zrs   80s
```

```powrshell
kubectl exec nginx-lrs-7db4886f8c-x4hzz -it -- cat /mnt/azuredisk/outfile
# Tue Mar 21 15:00:14 UTC 2023
# Tue Mar 21 15:01:14 UTC 2023
# Tue Mar 21 15:02:14 UTC 2023
# Tue Mar 21 15:03:14 UTC 2023

kubectl exec nginx-zrs-5567fd9ddc-hbtfs -it -- cat /mnt/azuredisk/outfile
# Tue Mar 21 15:00:48 UTC 2023
# Tue Mar 21 15:01:48 UTC 2023
# Tue Mar 21 15:02:48 UTC 2023
# Tue Mar 21 15:03:48 UTC 2023
```