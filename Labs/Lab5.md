## Lab 5: Provision/enable NetApp Files NFS volumes, SMB volumes and dual-protocol volumes

A persistent volume represents a piece of storage that has been provisioned for use with Kubernetes pods. A persistent volume can be used by one or many pods, and it can be statically or dynamically provisioned. This Lab shows you how to configure Azure NetApp Files to be used by pods on an Azure Kubernetes Service (AKS) cluster.

Azure NetApp Files is an enterprise-class, high-performance, metered file storage service running on Azure and supports volumes using NFS (NFSv3 or NFSv4.1), SMB, and dual-protocol (NFSv3 and SMB, or NFSv4.1 and SMB). Kubernetes users have two options for using Azure NetApp Files volumes for Kubernetes workloads:

- **Create Azure NetApp Files volumes statically**. In this scenario, the creation of volumes is external to AKS. Volumes are created using the Azure CLI or from the Azure portal, and are then exposed to Kubernetes by the creation of a PersistentVolume. Statically created Azure NetApp Files volumes have many limitations (for example, inability to be expanded, needing to be over-provisioned, and so on). Statically created volumes aren't recommended for most use cases.
- **Create Azure NetApp Files volumes dynamically**, orchestrating through Kubernetes. This method is the preferred way to create multiple volumes directly through Kubernetes, and is achieved using Astra Trident. Astra Trident is a CSI-compliant dynamic storage orchestrator that helps provision volumes natively through Kubernetes.

**NOTE:** Dual-protocol volumes can only be created statically. 

Using a CSI driver to directly consume Azure NetApp Files volumes from AKS workloads is the recommended configuration for most use cases. This requirement is accomplished using Astra Trident, an open-source dynamic storage orchestrator for Kubernetes. Astra Trident is an enterprise-grade storage orchestrator purpose-built for Kubernetes, and fully supported by NetApp. It simplifies access to storage from Kubernetes clusters by automating storage provisioning.

You can take advantage of Astra Trident's Container Storage Interface (CSI) driver for Azure NetApp Files to abstract underlying details and create, expand, and snapshot volumes on-demand. Also, using Astra Trident enables you to use Astra Control Service built on top of Astra Trident. Using the Astra Control Service, you can backup, recover, move, and manage the application-data lifecycle of your AKS workloads across clusters within and across Azure regions to meet your business and service continuity needs.

Let's start by creating a new NetFiles Account and pool.

```powershell
az netappfiles account create --resource-group $RESOURCE_GROUP --location $LOCATION --account-name $ANF_ACCOUNT_NAME
az netappfiles pool create --resource-group $RESOURCE_GROUP --location $LOCATION --account-name $ANF_ACCOUNT_NAME --pool-name $POOL_NAME --size $SIZE --service-level $SERVICE_LEVEL
```

Now we need to create a new Subnet for the Azure NetApp Files service. This subnet must be in the same virtual network as your AKS cluster.

```powershell
az network vnet subnet create --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name $SUBNET_NAME --delegations "Microsoft.Netapp/volumes" --address-prefixes $ADDRESS_PREFIX
```

### 1. Provision Azure NetApp Files NFS volumes for Azure Kubernetes Service

This section describes how to create an NFS volume on Azure NetApp Files and expose the volume statically to Kubernetes. It also describes how to use the volume with a containerized application.

Create a volume using the az netappfiles volume create command:

```powershell
az netappfiles volume create --resource-group $RESOURCE_GROUP --location $LOCATION --account-name $ANF_ACCOUNT_NAME --pool-name $POOL_NAME --name "$VOLUME_NAME" --service-level $SERVICE_LEVEL --vnet $VNET_ID --subnet $SUBNET_ID --usage-threshold $VOLUME_SIZE_GIB --file-path $UNIQUE_FILE_PATH --protocol-types NFSv3
```
With the volume creates, we can now create the persistent volume using the kubectl apply command:

```powershell
kubectl apply -f pv-nfs.yaml
```

Verify the status of the persistent volume is Available by using the kubectl describe command:

```powershell
kubectl describe pv pv-nfs
```

Now lets create the persistent volume claim using the kubectl apply command:

```powershell
kubectl apply -f pvc-nfs.yaml
```

Verify the Status of the persistent volume claim is Bound by using the kubectl describe command:
```powershell
kubectl describe pvc pvc-nfs
```

Now lets mount this volume to a pod in AKS.
Create the pod using the kubectl apply command:

```powershell
kubectl apply -f nginx-nfs.yaml
```

Verify the pod is Running by using the kubectl describe command:

```powershell
kubectl describe pod nginx-nfs
```

Verify your volume has been mounted on the pod by using kubectl exec to connect to the pod, and then use df -h to check if the volume is mounted.

```powershell
kubectl exec -it nginx-nfs -- sh
```
```output
/ # df -h
Filesystem             Size  Used Avail Use% Mounted on
...
10.0.0.4:/myfilepath2  100T  384K  100T   1% /mnt/azure
...
```

### 2. Provision Azure NetApp Files SMB volumes for Azure Kubernetes Service



### 3. Provision Azure NetApp Files dual-protocol volumes for Azure Kubernetes Service
