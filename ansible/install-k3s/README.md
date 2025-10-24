
# K3s Installation with Native Ceph Storage

This playbook installs K3s (lightweight Kubernetes) with native Ceph storage deployed via Rook operator on NVMe drives.

## Features

- **K3s Cluster**: Lightweight Kubernetes distribution with etcd on NVMe
- **Cilium CNI**: Advanced networking and security
- **Native Ceph Storage**: Ceph cluster deployed directly on NVMe partitions
- **Rook Operator**: Kubernetes-native Ceph management
- **CSI Driver**: Container Storage Interface for dynamic provisioning
- **Default Storage**: Ceph RBD as default StorageClass

## Prerequisites

1. **NVMe Partitioning**: Master nodes must have NVMe drives partitioned
   - 10GiB partition for K3s etcd (`/var/lib/rancher/k3s`)
   - Remaining space for Ceph OSDs
   - Use the `../nvme-partitioning/` playbook first

2. **Master Nodes**: At least 3 master nodes (blade001-blade003)
   - Each with NVMe drive at `/dev/nvme0n1`
   - Partition 2 (`/dev/nvme0n1p2`) available for Ceph

## Installation

```bash
bash install.sh
```

## What Gets Installed

### Core K3s Components
- K3s server and agents (etcd on NVMe)
- Cilium CNI plugin
- CoreDNS
- Metrics server

### Native Ceph Storage
- **Rook Operator**: Manages Ceph cluster
- **CephCluster**: Native Ceph deployment on NVMe drives
- **3 Monitors**: Distributed across master nodes
- **2 Managers**: With dashboard enabled
- **3 OSDs**: Using NVMe partition 2 on each master

### Storage Features
- **Default StorageClass**: `ceph-rbd` (replaces local-path)
- **Dynamic Provisioning**: Automatic PV creation
- **Volume Expansion**: Resize volumes on demand
- **RBD Backend**: High-performance NVMe-backed storage
- **3-way Replication**: Data protection across nodes

## Using External Ceph Storage

### Basic PVC Example
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: ceph-external-sc
```

See `ceph-pvc-example.yaml` for more comprehensive examples.

## Validation

After installation, verify the integration:

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Check Ceph integration
kubectl get cephcluster -n rook
kubectl get storageclass ceph-external-sc

# Test with a PVC
kubectl apply -f ceph-pvc-example.yaml
kubectl get pvc
```

## Troubleshooting

For detailed troubleshooting information, see:
- `EXTERNAL_CEPH_TROUBLESHOOTING.md` - Comprehensive troubleshooting guide
- Logs: `kubectl logs -n rook deployment/rook-ceph-operator`
- Ceph status: `cephadm shell -- ceph status` (run on blade001)

## Configuration

### Hosts
Edit `hosts.yaml` to define your cluster nodes:
- `bootstrapMaster`: Initial K3s server (should be blade001 with Ceph)
- `masters`: Additional K3s servers
- `workers`: K3s agent nodes

### Variables
Key variables in the playbook:
- `cleanup_test_pvc`: Set to `true` to clean up test PVC after validation
- Ceph cluster details are automatically extracted from the running cluster

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   K3s Cluster   │    │  Ceph Cluster   │
│  (blade001-005) │    │  (blade001-005) │
├─────────────────┤    ├─────────────────┤
│ • K3s Server    │◄──►│ • Monitors      │
│ • K3s Agents    │    │ • OSDs          │
│ • Rook Operator │    │ • Managers      │
│ • CSI Driver    │    │ • RBD Pool      │
└─────────────────┘    └─────────────────┘
        │                       │
        └───────────────────────┘
              Storage Network
```

## Uninstallation

```bash
bash uninstall.sh
```

Note: This only removes K3s. The external Ceph cluster remains intact.

## Next Steps

After installation:
1. Deploy applications using `ceph-external-sc` StorageClass
2. Set up monitoring for both K3s and Ceph
3. Configure backup solutions for persistent data
4. Implement RBAC and security policies
