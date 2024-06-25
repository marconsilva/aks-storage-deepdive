# Requires -Version 5.1

# Set strict mode
Set-StrictMode -Version Latest

$ver = "master"
if ($args.Count -gt 0) {
    $ver = $args[0]
}

$repo = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-iscsi/$ver/deploy"
if ($args.Count -gt 1) {
    if ($args[1] -like "*local*") {
        Write-Host "use local deploy"
        $repo = "./deploy"
    }
}

if ($ver -ne "master") {
    $repo = "$repo/$ver"
}

Write-Host "Installing iscsi.csi.k8s.io CSI driver, version: $ver ..."
kubectl apply -f $repo/csi-iscsi-driverinfo.yaml
kubectl apply -f $repo/csi-iscsi-node.yaml
Write-Host 'iscsi.csi.k8s.io CSI driver installed successfully.'