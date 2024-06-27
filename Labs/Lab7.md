
## Lab 7: Configure Backup on a cluster and how to use Resource Modification to patch backed-up

Azure Kubernetes Service (AKS) backup is a simple, cloud-native process you can use to back up and restore containerized applications and data that run in your AKS cluster. You can configure scheduled backups for cluster state and application data that's stored on persistent volumes in CSI driver-based Azure Disk Storage. The solution gives you granular control to choose a specific namespace or an entire cluster to back up or restore by storing backups locally in a blob container and as disk snapshots. You can use AKS backup for end-to-end scenarios, including operational recovery, cloning developer/test environments, and cluster upgrade scenarios.

Use AKS backup to back up your AKS workloads and persistent volumes that are deployed in AKS clusters. The solution requires the Backup extension to be installed inside the AKS cluster. The Backup vault communicates to the extension to complete operations that are related to backup and restore. Using the Backup extension is mandatory, and the extension must be installed inside the AKS cluster to enable backup and restore for the cluster. When you configure AKS backup, you add values for a storage account and a blob container where backups are stored.

# Backup and Restore AKS using Azure CLI

This document outlines the steps to backup and restore Azure Kubernetes Service (AKS) clusters using Azure CLI commands.

## Prerequisites

Before you begin, ensure you have the following:

- An Azure subscription
- Azure CLI installed
- Permissions to register resource providers and create resources in your Azure subscription

## Register Azure Providers

Register the necessary Azure providers for Kubernetes configuration and container service.

```bash
az provider register --namespace Microsoft.KubernetesConfiguration
az feature register --namespace "Microsoft.ContainerService" --name "TrustedAccessPreview"
```

Add the Variables

```bash
$VAULT_NAME="backup-vault"
$VAULT_RG="rg-backup-vault"
$SA_NAME="storage4aks1backupdemoms"
$SA_RG="rg-backup-storage"
$BLOB_CONTAINER_NAME="aks-backup"
$SUBSCRIPTION_ID=$(az account list --query [?isDefault].id -o tsv)
$AKS_RG_01="aksstoragelab"
$AKS_01="aksstoragelab"
```

## Step 1: Setup Backup Infrastructure

### Create a Resource Group for Backup Vault
```bash
az group create --name $VAULT_RG --location westeurope
```

### Create the Backup vault
```bash
az dataprotection backup-vault create --vault-name $VAULT_NAME -g $VAULT_RG --storage-setting "[{type:'LocallyRedundant',datastore-type:'VaultStore'}]"
```

### Create a Backup Policy

```bash
az dataprotection backup-policy get-default-policy-template --datasource-type AzureKubernetesService > akspolicy.json
az dataprotection backup-policy create -g $VAULT_RG --vault-name $VAULT_NAME -n aksmbckpolicy --policy akspolicy.json
```
   
2. Create storage account and Blob container for storing Backup data

```bash
az group create --name $SA_RG --location westeurope

az storage account create --name $SA_NAME --resource-group $SA_RG --sku Standard_LRS

az storage container create --name $BLOB_CONTAINER_NAME --account-name $SA_NAME --auth-mode login
```

3. Update the AKS Cluster to install the Backup extension

```bash
az aks update -g $AKS_RG_01 -n $AKS_01 --enable-disk-driver --enable-snapshot-controller
```

4. Install the Backup extension in first AKS cluster

```bash
az extension add --name k8s-extension

az k8s-extension create --name azure-aks-backup --extension-type Microsoft.DataProtection.Kubernetes --scope cluster --cluster-type managedClusters --cluster-name $AKS_01 --resource-group $AKS_RG_01 --release-train stable --configuration-settings blobContainer=$BLOB_CONTAINER_NAME storageAccount=$SA_NAME storageAccountResourceGroup=$SA_RG storageAccountSubscriptionId=$SUBSCRIPTION_ID


# View Backup Extension installation status

az k8s-extension show --name azure-aks-backup --cluster-type managedClusters --cluster-name $AKS_01 -g $AKS_RG_01
```

We can see that is using Velero

```bash
kubectl describe pod -n dataprotection-microsoft | grep -i image:
```

5. As part of extension installation, a user identity is created in the AKS cluster's Node Pool Resource Group. For the extension to access the storage account, you need to provide this identity the Storage Blob Data Contributor role. To assign the required role, run the following command:

```bash
az role assignment create --assignee-object-id $(az k8s-extension show --name azure-aks-backup --cluster-name $AKS_01 --resource-group $AKS_RG_01 --cluster-type managedClusters --query aksAssignedIdentity.principalId --output tsv) --role 'Storage Blob Data Contributor' --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$SA_RG/providers/Microsoft.Storage/storageAccounts/$SA_NAME
```

6. Enable Trusted Access in AKS

```bash
$BACKUP_VAULT_ID=$(az dataprotection backup-vault show --vault-name $VAULT_NAME -g $VAULT_RG --query id -o tsv)

az aks trustedaccess rolebinding create -g $AKS_RG_01 --cluster-name $AKS_01 --name backuprolebinding --source-resource-id $BACKUP_VAULT_ID --roles Microsoft.DataProtection/backupVaults/backup-operator

az aks trustedaccess rolebinding list -g $AKS_RG_01 --cluster-name $AKS_01
```

## Configure the Backup and Create a Backup Instance

1. Initialize the backup configuration

```bash
az dataprotection backup-instance initialize-backupconfig --datasource-type AzureKubernetesService > aksbackupconfig.json

# If you want to add only backup to specific namespace or resource change the generated config.json
# {
#  "excluded_namespaces": null,
#  "excluded_resource_types": null,
#  "include_cluster_scope_resources": true,
#  "included_namespaces": null, 
#  "included_resource_types": null,
#  "label_selectors": null,
#  "snapshot_volumes": true
# }

```

2. Initialize the backup-instance

```bash
az dataprotection backup-instance initialize --datasource-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AKS_RG_01/providers/Microsoft.ContainerService/managedClusters/$AKS_01 --datasource-location westeurope --datasource-type AzureKubernetesService --policy-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$VAULT_RG/providers/Microsoft.DataProtection/backupVaults/$VAULT_NAME/backupPolicies/aksmbckpolicy --backup-configuration ./aksbackupconfig.json --friendly-name ecommercebackup --snapshot-resource-group-name $AKS_RG_01 > backupinstance.json


# validate the backup instance
az dataprotection backup-instance validate-for-backup --backup-instance ./backupinstance.json --ids /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$VAULT_RG/providers/Microsoft.DataProtection/backupVaults/$VAULT_NAME
```	

If the validation fails and there are certain permissions missing, then you can assign them by running the following command:

```bash
az dataprotection backup-instance update-msi-permissions --datasource-type AzureKubernetesService --operation Backup --permissions-scope ResourceGroup --vault-name $VAULT_NAME --resource-group $VAULT_RG --backup-instance backupinstance.json
```

3. Create the Backup Instance

```bash
az dataprotection backup-instance create --backup-instance  backupinstance.json --resource-group $VAULT_RG --vault-name $VAULT_NAME
```

## Run an on-demand backup

1. To fetch the relevant backup instance on which you want to trigger a backup, run the az dataprotection backup-instance list-from-resourcegraph -- command

```bash
az dataprotection backup-instance list-from-resourcegraph --datasource-type AzureKubernetesService --datasource-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AKS_RG_01/providers/Microsoft.ContainerService/managedClusters/$AKS_01 
```

```bash
BACKUP_INSTANCE_ID="aksstoragelab-aksstoragelab-aksstoragelab"
```

2. Fetch the rule name of the policy for the next command

```bash
az dataprotection backup-policy show -g $VAULT_RG --vault-name $VAULT_NAME -n "aksmbckpolicy"

# Now, trigger an on-demand backup for the backup instance by running the following command (backuninstanceid from previous command):
az dataprotection backup-instance adhoc-backup --rule-name "BackupHourly" --ids /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$VAULT_RG/providers/Microsoft.DataProtection/backupVaults/$VAULT_NAME/backupInstances/$BACKUP_INSTANCE_ID
```

3. Tracking the jobs 

```bash
#For on-demand backup:
az dataprotection job list-from-resourcegraph --datasource-type AzureKubernetesService --datasource-id /subscriptions/fef74fbe-24ca-4d9a-ba8e-30a17e95608b/resourceGroups/ChaosStudio/providers/Microsoft.ContainerService/managedClusters/$AKS_01 --operation OnDemandBackup

# For scheduled backup:
az dataprotection job list-from-resourcegraph --datasource-type AzureKubernetesService --datasource-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AKS_RG_01/providers/Microsoft.ContainerService/managedClusters/$AKS_01 --operation ScheduledBackup
```
We can check the backup also stored on the storage account and on the backup vault


# Restore

For restore, we need to have the backup instance id and the recovery point id. Let's remove some namespaces and restore the original state of the system. We could ad a different cluster to restore to that new cluster my previously backup. But for this scenario let's create some disruptions on current cluster and then restore to original state.

```bash
kubectl delete ns my-namespace1
kubectl delete ns my-namespace2
kubectl delete my-resources (ns, deployments)
```

1. First, check if Backup Extension is installed in the cluster by running the following command:

```bash
az k8s-extension show --name azure-aks-backup --cluster-type managedClusters --cluster-name $AKS_01 --resource-group $AKS_RG_01
```

2. If the extension is installed, then check if it has the right permissions on the storage account where backups are stored:

```bash
az role assignment list --all --assignee  $(az k8s-extension show --name azure-aks-backup --cluster-name $AKS_01 --resource-group $AKS_RG_01 --cluster-type managedClusters --query aksAssignedIdentity.principalId --output tsv)
```

3. If the role isn't assigned, then you can assign the role by running the following command:

```bash
az role assignment create --assignee-object-id $(az k8s-extension show --name azure-aks-backup --cluster-name $AKS_01 --resource-group $AKS_RG_01 --cluster-type managedClusters --query aksAssignedIdentity.principalId --output tsv) --role 'Storage Account Contributor'  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$SA_RG/providers/Microsoft.Storage/storageAccounts/$SA_NAME
```

4. Check Trusted Access is enabled between the Backup vault and Target AKS cluster

```bash
az aks trustedaccess rolebinding list --resource-group $AKS_RG_01 --cluster-name $AKS_01
```	

If it's not enabled, then run the following command to enable Trusted Access:

```bash	
az aks trustedaccess rolebinding create --cluster-name $AKS_01 --name backuprolebinding --resource-group $AKS_RG_01 --roles Microsoft.DataProtection/backupVaults/backup-operator --source-resource-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$VAULT_RG/providers/Microsoft.DataProtection/BackupVaults/$VAULT_NAME
```

## Restore to an AKS cluster

5. Fetch all instances associated with the AKS cluster and identify the relevant instance.

```bash
az dataprotection backup-instance list-from-resourcegraph --datasource-type AzureKubernetesService --datasource-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AKS_RG_01/providers/Microsoft.ContainerService/managedClusters/$AKS_01 
```

Once the instance is identified, fetch the relevant recovery point (retrieve the BACKUP_INSTANCE_NAME from the previous command).

```bash
az dataprotection recovery-point list --backup-instance-name $BACKUP_INSTANCE_NAME --resource-group $VAULT_RG --vault-name $VAULT_NAME
```

## Prepare the restore request

6. To prepare the restore configuration defining the items to be restored to the target AKS cluster, run the az dataprotection backup-instance initialize-restoreconfig command.

```bash
az dataprotection backup-instance initialize-restoreconfig --datasource-type AzureKubernetesService >restoreconfig.json
```

Now, prepare the restore request with all relevant details. If you're restoring the backup to the original cluster, then run the following command (choose a specific RECOVERY_POINT_ID from the previous command, and also chose a REGION for the restore location):

```bash
az dataprotection backup-instance restore initialize-for-item-recovery --datasource-type AzureKubernetesService --restore-location "westeurope" --source-datastore OperationalStore --recovery-point-id $RECOVERY_POINT_ID --restore-configuration restoreconfig.json --backup-instance-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$VAULT_RG/providers/Microsoft.DataProtection/backupVaults/$VAULT_NAME/backupInstances/$BACKUP_INSTANCE_NAME >restorerequestobject.json
```

7. Now, you can update the JSON object as per your requirements, and then validate the object by running the following command:

```bash
az dataprotection backup-instance validate-for-restore --backup-instance-name $BACKUP_INSTANCE_NAME --resource-group $VAULT_RG --restore-request-object restorerequestobject.json --vault-name $VAULT_NAME

```

If everything is working correctly we will see an output like

```bash
{
    "objectType": "OperationJobExtendedInfo"
}
```	

8. The previous command checks if the AKS Cluster and Backup vault have required permissions on each other and the Snapshot resource group to perform restore. If the validation fails due to missing permissions, you can assign them by running the following command:

```bash
az dataprotection backup-instance update-msi-permissions --datasource-type AzureKubernetesService --operation Restore --permissions-scope Resource --resource-group  $VAULT_RG --vault-name $VAULT_NAME --restore-request-object restorerequestobject.json --snapshot-resource-group-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AKS_RG_01
```

## Trigger the restore

9. Once the validation is successful, you can trigger the restore by running the following command:

```bash
az dataprotection backup-instance restore trigger --restore-request-object restorerequestobject.json --ids /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$VAULT_RG/providers/Microsoft.DataProtection/backupVaults/$VAULT_NAME/backupInstances/$BACKUP_INSTANCE_NAME --name $BACKUP_INSTANCE_NAME
```

10. Tracking job

```bash
az dataprotection job list-from-resourcegraph --datasource-type AzureKubernetesService --datasource-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AKS_RG_01/providers/Microsoft.ContainerService/managedClusters/$AKS_01 --operation Restore
```

You can now check on the AKS cluster if the namespaces are restored and under the AKS backup portal the progress of the restore job.

## Clean up

```bash
az group delete --name $VAULT_RG --yes
az group delete --name $SA_RG --yes
```

## References

- [Azure Kubernetes Service (AKS) backup and restore](https://docs.microsoft.com/en-us/azure/aks/backup-restore)
- [Azure Kubernetes Service (AKS) backup and restore using Azure CLI](https://docs.microsoft.com/en-us/azure/aks/backup-restore-cli)
