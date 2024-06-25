
## Lab 1: Provision/enable CSI Storage Drivers and expand without downtime

The Container Storage Interface (CSI) is a standard for exposing arbitrary block and file storage systems to containerized workloads on Kubernetes. By adopting and using CSI, Azure Kubernetes Service (AKS) can write, deploy, and iterate plug-ins to expose new or improve existing storage systems in Kubernetes without having to touch the core Kubernetes code and wait for its release cycles.

The CSI storage driver support on AKS allows you to natively use:

- **Azure Disks** can be used to create a Kubernetes DataDisk resource. Disks can use Azure Premium Storage, backed by high-performance SSDs, or Azure Standard Storage, backed by regular HDDs or Standard SSDs. For most production and development workloads, use Premium Storage. Azure Disks are mounted as ReadWriteOnce and are only available to one node in AKS. For storage volumes that can be accessed by multiple nodes simultaneously, use Azure Files.
- **Azure Files** can be used to mount an SMB 3.0/3.1 share backed by an Azure storage account to pods. With Azure Files, you can share data across multiple nodes and pods. Azure Files can use Azure Standard storage backed by regular HDDs or Azure Premium storage backed by high-performance SSDs.
- **Azure Blob** storage can be used to mount Blob storage (or object storage) as a file system into a container or pod. Using Blob storage enables your cluster to support applications that work with large unstructured datasets like log file data, images or documents, HPC, and others. Additionally, if you ingest data into Azure Data Lake storage, you can directly mount and use it in AKS without configuring another interim filesystem.

**IMPORTANT**

Starting with Kubernetes version 1.26, in-tree persistent volume types kubernetes.io/azure-disk and kubernetes.io/azure-file are deprecated and will no longer be supported. Removing these drivers following their deprecation is not planned, however you should migrate to the corresponding CSI drivers disk.csi.azure.com and file.csi.azure.com. 

### 1. Enable CSI Storage Drivers

Start by checking the current storage classes available in the AKS cluster.

```powershell	
kubectl get storageclass
```

```powershell	
PS C:\farfetch\aks-storage-deepdive> kubectl get storageclass
NAME                PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
default (default)   disk.csi.azure.com   Delete          WaitForFirstConsumer   true                   48m
PS C:\farfetch\aks-storage-deepdive>
```

Now enable the CSI drivers on the AKS cluster, and check the new storage classes available.

```powershell	
az aks update --name $CLUSTER --resource-group $RESOURCE_GROUP --enable-disk-driver --enable-file-driver --enable-blob-driver --enable-snapshot-controller
```

```powershell	
kubectl get storageclass
```

In addition to in-tree driver features, Azure Disk CSI driver supports the following features:

- Performance improvements during concurrent disk attach and detach
- In-tree drivers attach or detach disks in serial, while CSI drivers attach or detach disks in batch. There's significant improvement when there are multiple disks attaching to one node.
- Premium SSD v1 and v2 are supported.
  - PremiumV2_LRS only supports None caching mode
- Zone-redundant storage (ZRS) disk support
  - Premium_ZRS, StandardSSD_ZRS disk types are supported. ZRS disk could be scheduled on the zone or non-zone node, without the restriction that disk volume should be co-located in the same zone as a given node. For more information, including which regions are supported, see Zone-redundant storage for managed disks.
- Snapshot
- Volume clone
- Resize disk PV without downtime

### 2. Dynamically create Azure Disks PVs by using the built-in storage classes

When you use the Azure Disk CSI driver on AKS, there are two more built-in StorageClasses that use the Azure Disk CSI storage driver. The other CSI storage classes are created with the cluster alongside the in-tree default storage classes.

- **managed-csi**: Uses Azure Standard SSD locally redundant storage (LRS) to create a managed disk. Effective starting with Kubernetes version 1.29, in Azure Kubernetes Service (AKS) clusters deployed across multiple availability zones, this storage class utilizes Azure Standard SSD zone-redundant storage (ZRS) to create managed disks.
- **managed-csi-premium**: Uses Azure Premium LRS to create a managed disk. Effective starting with Kubernetes version 1.29, in Azure Kubernetes Service (AKS) clusters deployed across multiple availability zones, this storage class utilizes Azure Premium zone-redundant storage (ZRS) to create managed disks.

The reclaim policy in both storage classes ensures that the underlying Azure Disks are deleted when the respective PV is deleted. The storage classes also configure the PVs to be expandable. You just need to edit the persistent volume claim (PVC) with the new size.

Create an example pod and respective PVC by running the kubectl apply command:

```powershell	
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/example/pvc-azuredisk-csi.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/deploy/example/nginx-pod-azuredisk.yaml
```

After the pod is in the running state, run the following command to create a new file called test.txt.

```powershell	
kubectl exec nginx-azuredisk -- touch /mnt/azuredisk/test.txt
```

To validate the disk is correctly mounted, run the following command and verify you see the test.txt file in the output:

```powershell	
kubectl exec nginx-azuredisk -- ls /mnt/azuredisk
```

### 2. Expand Volume without downtime

You can request a larger volume for a PVC. Edit the PVC object, and specify a larger size. This change triggers the expansion of the underlying volume that backs the PV.

In AKS, the built-in managed-csi storage class already supports expansion, so use the PVC created earlier with this storage class. The PVC requested a 10-Gi persistent volume. You can confirm by running the following command:

```powershell	
kubectl exec -it nginx-azuredisk -- df -h /mnt/azuredisk
```

The output of the command resembles the following example:

```output	
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdc        9.8G   42M  9.8G   1% /mnt/azuredisk
```

Now we will expand the PVC by increasing the **spec.resources.requests.storage** field running the following command:

```powershell	
kubectl patch pvc pvc-azuredisk --type merge --patch '{"spec": {"resources": {"requests": {"storage": "15Gi"}}}}'
```

Run the following command to confirm the volume size has increased:

```powershell	
kubectl get pv
```

The output of the command resembles the following example:

```output	
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                     STORAGECLASS   REASON   AGE
pvc-391ea1a6-0191-4022-b915-c8dc4216174a   15Gi       RWO            Delete           Bound    default/pvc-azuredisk                     managed-csi             2d2h
(...)
```

And after a few minutes, run the following commands to confirm the size of the PVC:

```powershell	
kubectl get pvc pvc-azuredisk
```

The output of the command resembles the following example:

```output	
NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pvc-azuredisk   Bound    pvc-391ea1a6-0191-4022-b915-c8dc4216174a   15Gi       RWO            managed-csi    2d2h
```

Run the following command to confirm the size of the disk inside the pod:

```powershell	
kubectl exec -it nginx-azuredisk -- df -h /mnt/azuredisk
```

The output of the command resembles the following example:

```output	
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdc         15G   46M   15G   1% /mnt/azuredisk
```
