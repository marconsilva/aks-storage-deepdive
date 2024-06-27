## Lab 6: Provision/enable NVMe PV in AKS Nodepool

Azure Container Storage is a cloud-based volume management, deployment, and orchestration service built natively for containers. This Lab shows you how to configure Azure Container Storage to use Ephemeral Disk with local NVMe as back-end storage for your Kubernetes workloads. At the end, you'll have a pod that's using local NVMe as its storage.

When your application needs sub-millisecond storage latency and doesn't require data durability, you can use Ephemeral Disk with Azure Container Storage to meet your performance requirements. Ephemeral means that the disks are deployed on the local virtual machine (VM) hosting the AKS cluster and not saved to an Azure storage service. Data will be lost on these disks if you stop/deallocate your VM.

There are two types of Ephemeral Disk available: NVMe and temp SSD. NVMe is designed for high-speed data transfer between storage and CPU. Choose NVMe when your application requires higher IOPS and throughput than temp SSD, or if your workload requires replication. Replication isn't currently supported for temp SSD.

In this lab we will be working with NVMe disks.

### 1. Choosing a VM Type that supports Temp SSD

Ephemeral Disk is only available in certain types of VMs. If you plan to use local NVMe, a storage optimized VM such as standard_l8s_v3 is required.

we will need to create a new AKS Node Pool with the required VM type.

```powershell
az aks nodepool add --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER --name nvme --node-count 3 --node-vm-size Standard_L16s_v3 --node-osdisk-type Ephemeral --Label "acstor.azure.com/io-engine=acstor"
```

### 2. Creating the Storage Pool
First we will need to create a storage pool, which is a logical grouping of storage for your Kubernetes cluster.

Lets run the following commands to create the storage pool.

```powershell
kubectl apply -f acstor-storagepool-nvme.yaml
```
You can run this command to check the status of the storage pool:

```powershell
kubectl describe sp ephemeraldisknvme -n acstor
```

When the storage pool is created, Azure Container Storage will create a storage class on your behalf, using the naming convention acstor-<storage-pool-name>.

You can check the status of the storage class by running the following command:

```powershell
kubectl get sc
```

**NOTE:** Don't use the storage class that's marked internal. It's an internal storage class that's needed for Azure Container Storage to work.

Now lets see it in action and create a pod that uses the storage class.
First lets create a pod that uses Fio (Flexible I/O Tester) for benchmarking and workload simulation, that uses a generic ephemeral volume.

```powershell
kubectl apply -f acstor-pod-nvme.yaml
```

Check that the pod is running and that the ephemeral volume claim has been bound successfully to the pod:

```powershell
kubectl describe pod fiopod-nvme
kubectl describe pvc fiopod-nvme-ephemeralvolume
```

Now lets run a benchmark on the pod to see the performance of the temp SSD.

```powershell
kubectl exec -it fiopod -- fio-nvme --name=benchtest --size=800m --filename=/volume/test --direct=1 --rw=randrw --ioengine=libaio --bs=4k --iodepth=16 --numjobs=8 --time_based --runtime=60
```

