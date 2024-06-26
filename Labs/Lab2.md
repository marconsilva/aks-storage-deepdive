
## Lab 2: Provision/enable Azure Elastic SAN in an existing AKS Cluster using iSCSI CSI driver

This Lab explains how to connect an Azure Elastic storage area network (SAN) volume from an Azure Kubernetes Service (AKS) cluster. To make this connection, enable the Kubernetes iSCSI CSI driver on your cluster. With this driver, you can access volumes on your Elastic SAN by creating persistent volumes on your AKS cluster, and then attaching the Elastic SAN volumes to the persistent volumes.

### 1. About the iSCSI CSI driver
The iSCSI CSI driver is an open source project that allows you to connect to a Kubernetes cluster over iSCSI. Since the driver is an open source project, Microsoft won't provide support from any issues stemming from the driver, itself.

The Kubernetes iSCSI CSI driver is available on GitHub:

- [Kubernetes iSCSI CSI driver repository](https://github.com/kubernetes-csi/csi-driver-iscsi)
- [Readme](https://github.com/kubernetes-csi/csi-driver-iscsi/blob/master/README.md)
- [Report iSCSI driver issues](https://github.com/kubernetes-csi/csi-driver-iscsi/issues)

### 2. Deploy an Elastic SAN volume

The following command creates an Elastic SAN that uses zone-redundant storage.

```powershell	
az elastic-san create -n $EsanName -g $RESOURCE_GROUP -l $LOCATION --base-size-tib 50 --extended-capacity-size-tib 20 --sku "{name:Premium_ZRS,tier:Premium}"
```

Now that you've configured the basic settings and provisioned your storage, you can create volume groups. Volume groups are a tool for managing volumes at scale. Any settings or configurations applied to a volume group apply to all volumes associated with that volume group.

```powershell
az elastic-san volume-group create --elastic-san-name $EsanName -g $RESOURCE_GROUP -n $EsanVgName
```

Now that you've configured the SAN itself, and created at least one volume group, you can create volumes.

Volumes are usable partitions of the SAN's total capacity, you must allocate a portion of that total capacity as a volume in order to use it. Only the actual volumes themselves can be mounted and used, not volume groups.


```powershell
az elastic-san volume create --elastic-san-name $EsanName -g $RESOURCE_GROUP -v $EsanVgName -n $VolumeName --size-gib 2000
```

### 3. Using Kubernetes iSCSI CSI driver with Azure Elastic SAN

Before we start check to see that the driver isn't installed and then run the following script to install the driver.

```powershell	
kubectl -n kube-system get pod -o wide -l app=csi-iscsi-node
```

```powershell	
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install-driver.ps1
```
After deployment, check the pods status again to verify that the driver installed.

```powershell	
kubectl -n kube-system get pod -o wide -l app=csi-iscsi-node
```

Now lets get all the information needed to connect the Elastic SAN volume that was created previously to the AKS cluster.

```powershell	
az elastic-san volume show -g $RESOURCE_GROUP -e $EsanName -v $EsanVgName -n $VolumeName
```

from the output extract the following information:
- **targetPortalHostname**
- **targetPortalPort**
- **targetIqn**

Now you will need to make a copy of the esan-pv.yaml file and replace the placeholders with the information you got from the previous command.

After creating the pv.yml file, create a persistent volume with the following command:

```powershell	
kubectl apply -f pathtoyourfile/esan-pv.yaml
```

now lets create a namespace **aksesan**
    
```powershell
kubectl create ns aksesan
```

Next, create a persistent volume claim. Use the storage class we defined earlier with the persistent volume we defined. Simply run the following command:

```powershell
kubectl apply -f esan-pvc.yaml
```

To verify your PersistentVolumeClaim is created and bound to the PersistentVolume, run the following command:

```powershell
kubectl get pvc iscsiplugin-pvc
```

Finally lets create a pod manifest that uses this volume.

```powershell
kubectl apply -f esan-pod.yaml
kubectl apply -f esan-pod-service.yaml
```

