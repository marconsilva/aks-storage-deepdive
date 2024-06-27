## Lab 5: Provision/enable NetApp Files NFS volumes, SMB volumes and dual-protocol volumes

A persistent volume represents a piece of storage that has been provisioned for use with Kubernetes pods. A persistent volume can be used by one or many pods, and it can be statically or dynamically provisioned. This Lab shows you how to configure Azure NetApp Files to be used by pods on an Azure Kubernetes Service (AKS) cluster.

Azure NetApp Files is an enterprise-class, high-performance, metered file storage service running on Azure and supports volumes using NFS (NFSv3 or NFSv4.1), SMB, and dual-protocol (NFSv3 and SMB, or NFSv4.1 and SMB). Kubernetes users have two options for using Azure NetApp Files volumes for Kubernetes workloads:

- **Create Azure NetApp Files volumes statically**. In this scenario, the creation of volumes is external to AKS. Volumes are created using the Azure CLI or from the Azure portal, and are then exposed to Kubernetes by the creation of a PersistentVolume. Statically created Azure NetApp Files volumes have many limitations (for example, inability to be expanded, needing to be over-provisioned, and so on). Statically created volumes aren't recommended for most use cases.
- **Create Azure NetApp Files volumes dynamically**, orchestrating through Kubernetes. This method is the preferred way to create multiple volumes directly through Kubernetes, and is achieved using Astra Trident. Astra Trident is a CSI-compliant dynamic storage orchestrator that helps provision volumes natively through Kubernetes.

**NOTE:** Dual-protocol volumes can only be created statically. 

Using a CSI driver to directly consume Azure NetApp Files volumes from AKS workloads is the recommended configuration for most use cases. This requirement is accomplished using Astra Trident, an open-source dynamic storage orchestrator for Kubernetes. Astra Trident is an enterprise-grade storage orchestrator purpose-built for Kubernetes, and fully supported by NetApp. It simplifies access to storage from Kubernetes clusters by automating storage provisioning.

You can take advantage of Astra Trident's Container Storage Interface (CSI) driver for Azure NetApp Files to abstract underlying details and create, expand, and snapshot volumes on-demand. Also, using Astra Trident enables you to use Astra Control Service built on top of Astra Trident. Using the Astra Control Service, you can backup, recover, move, and manage the application-data lifecycle of your AKS workloads across clusters within and across Azure regions to meet your business and service continuity needs.

First some Pre-requisites are needed to be done before we can start with the lab.

For this lab we will need to extend the vnet space of the AKS Cluster vnet to add a subnet for the new Azure NetApp Files account and pool.

To do this we will need to set some variables for the rest of the lab to work.

```powershell
$VNET_ID="" # Replace with the vnet id from the AKS cluster
$VNET_NAME="" # Replace with the vnet name from the AKS cluster
$RESOURCE_GROUP_MC="" # Replace with the resource group name of the AKS cluster
$SUBNET_NAME="aksstoragelabANFSubnet"
$ADDRESS_PREFIX="10.225.0.0/16"
```

Let's start by creating a new NetFiles Account and pool.

```powershell
az netappfiles account create --resource-group $RESOURCE_GROUP --location $LOCATION --account-name $ANF_ACCOUNT_NAME

az netappfiles pool create --resource-group $RESOURCE_GROUP --location $LOCATION --account-name $ANF_ACCOUNT_NAME --pool-name $POOL_NAME --size $SIZE --service-level $SERVICE_LEVEL

```

Now we need to create a new Subnet for the Azure NetApp Files service. This subnet must be in the same virtual network as your AKS cluster.

```powershell
az network vnet subnet create --resource-group $RESOURCE_GROUP_MC --vnet-name $VNET_NAME --name $SUBNET_NAME --delegations "Microsoft.Netapp/volumes" --address-prefixes $ADDRESS_PREFIX
```

Now save the subnet id to a variable for later use.

```powershell
$SUBNET_ID=(az network vnet subnet show --resource-group $RESOURCE_GROUP_MC --vnet-name $VNET_NAME --name $SUBNET_NAME --query id -o tsv)
```

### 1. Provision Azure NetApp Files NFS volumes for Azure Kubernetes Service

This section describes how to create an NFS volume on Azure NetApp Files and expose the volume statically to Kubernetes. It also describes how to use the volume with a containerized application.

Create a volume using the az netappfiles volume create command:

```powershell
az netappfiles volume create --resource-group $RESOURCE_GROUP --location $LOCATION --account-name $ANF_ACCOUNT_NAME --pool-name $POOL_NAME --name "$VOLUME_NAME" --service-level $SERVICE_LEVEL --vnet $VNET_ID --subnet $SUBNET_ID --usage-threshold $VOLUME_SIZE_GIB --file-path $UNIQUE_FILE_PATH --protocol-types NFSv3
```

Retrieve the volume information using the az netappfiles volume show command:

```powershell
az netappfiles volume show --resource-group $RESOURCE_GROUP --account-name $ANF_ACCOUNT_NAME --pool-name $POOL_NAME --volume-name "$VOLUME_NAME" -o JSON
```

Make sure the server matches the output IP address from Step 1, and the path matches the output from creationToken above. The capacity must also match the volume size from the step above. 

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

### 2. Dynamically configure for applications that use NFS volumes

Astra Trident may be used to dynamically provision NFS or SMB files on Azure NetApp Files. Dynamically provisioned SMB volumes are only supported with windows worker nodes. This section describes how to use Astra Trident to dynamically create an NFS volume on Azure NetApp Files and automatically mount it to a containerized application.

Lets first install Astra Trident using Helm

```powershell
helm repo add netapp-trident https://netapp.github.io/trident-helm-chart   
helm install trident netapp-trident/trident-operator --version 23.04.0  --create-namespace --namespace trident

kubectl describe torc trident
```

To instruct Astra Trident about the Azure NetApp Files subscription and where it needs to create volumes, a backend is created. This step requires details about the account that was created in a previous step.

Using the file already created **backend-secret.yaml** as a template, change the Client ID and clientSecret to the correct values for your environment. also using the file already created **backend-anf.yaml** as a template, change the **subscriptionID** and **tenantID** to the correct values for your environment. 

Use the subscriptionID for the Azure subscription where Azure NetApp Files is enabled. Obtain the tenantID, clientID, and clientSecret from an application registration in Microsoft Entra ID with sufficient permissions for the Azure NetApp Files service. The application registration includes the Owner or Contributor role predefined by Azure. The location must be an Azure location that contains at least one delegated subnet created in a previous step. The serviceLevel must match the serviceLevel configured for the capacity pool in Configure Azure NetApp Files for AKS workloads.

You can now create the backend using the kubectl apply command:

```powershell
kubectl create namespace trident
kubectl apply -f backend-secret.yaml -n trident
kubectl apply -f backend-anf.yaml -n trident
kubectl get tridentbackends -n trident
```

A storage class is used to define how a unit of storage is dynamically created with a persistent volume. To consume Azure NetApp Files volumes, a storage class must be created.

```powershell	
kubectl apply -f anf-storageclass.yaml
kubectl get sc
```

Now we can create a PVC using the kubectl apply command:

```powershell
kubectl apply -f anf-pvc.yaml
kubectl get pvc
```

After the PVC is created, Astra Trident creates the persistent volume. A pod can be spun up to mount and access the Azure NetApp Files volume.

The following manifest can be used to define an NGINX pod that mounts the Azure NetApp Files volume created in the previous step. In this example, the volume is mounted at /mnt/data.

    
```powershell
kubectl apply -f anf-nginx-pod.yaml
kubectl describe pod nginx-pod
```

Verify the volume is mounted

```powershell
kubectl exec -it nginx-pod -- sh
df -h
```

```output
Events:
  Type    Reason                  Age   From                     Message
  ----    ------                  ----  ----                     -------
  Normal  Scheduled               15s   default-scheduler        Successfully assigned trident/nginx-pod to brameshb-non-root-test
  Normal  SuccessfulAttachVolume  15s   attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-bffa315d-3f44-4770-86eb-c922f567a075"
  Normal  Pulled                  12s   kubelet                  Container image "mcr.microsoft.com/oss/nginx/nginx:1.15.5-alpine" already present on machine
  Normal  Created                 11s   kubelet                  Created container nginx
  Normal  Started                 10s   kubelet     
```

### 3. Dynamically configure for applications that use SMB volumes

**PRE-REQUISITES:**
The AKS cluster must be set up with at least one Windows node pool. The AKS cluster must have connectivity to an Active Directory. Verify that the AKS host can resolve DNS to the AKS cluster.

See: https://techcommunity.microsoft.com/t5/azure-architecture-blog/azure-netapp-files-smb-volumes-for-azure-kubernetes-services/ba-p/3052900


With Astra Trident Already installed from previous lab, the following steps are needed to dynamically provision SMB volumes on Azure NetApp Files and automatically mount them to containerized applications.

Use the files **backend-secret-smb.yaml** and **backend-anf-smb.yaml** as a templates and change the Client ID and clientSecret to the correct values for your environment (same logic that previously backend created, and we can reuse the service principal clientID and TenantID, since it already has permissions).

Create the backend using the kubectl apply command:

```powershell
kubectl apply -f backend-secret.yaml -n trident
kubectl apply -f backend-anf.yaml -n trident
kubectl get tridentbackends -n trident
```

Create a secret with the domain credentials for SMB

Create a secret on your AKS cluster to access the AD server using the kubectl create secret command. This information will be used by the Kubernetes persistent volume to access the Azure NetApp Files SMB volume. Use the following command, replacing DOMAIN_NAME\USERNAME with your domain name and username and PASSWORD with your password.

```powershell	
kubectl create secret generic smbcreds --from-literal=username=DOMAIN_NAME\USERNAME –from-literal=password="PASSWORD"

kubectl get secrets
```

A storage class is used to define how a unit of storage is dynamically created with a persistent volume. To consume Azure NetApp Files volumes, a storage class must be created.

```powershell
kubectl apply -f anf-storageclass-smb.yaml
kubectl get sc anf-sc-smb
```

A persistent volume claim (PVC) is a request for storage by a user. Upon the creation of a persistent volume claim, Astra Trident automatically creates an Azure NetApp Files SMB share and makes it available for Kubernetes workloads to consume.

```powershell
kubectl apply -f anf-pvc-smb.yaml
kubectl get pvc
```

After the PVC is created, a pod can be spun up to access the Azure NetApp Files volume. The following manifest can be used to define an Internet Information Services (IIS) pod that mounts the Azure NetApp Files SMB share created in the previous step. In this example, the volume is mounted at /inetpub/wwwroot.


```powershell
kubectl apply -f anf-iis-deploy-pod.yaml
kubectl describe pod iis-pod
kubectl exec -it iis-pod –- cmd.exe
```
