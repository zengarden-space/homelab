# Ceph/Rook Cluster Deployment

This Ansible playbook deploys a native Ceph cluster using the Rook operator on an existing K3s cluster with partitioned NVMe drives.

## Overview

This playbook provides a complete Ceph storage solution by:

- Installing the Rook operator via Helm
- Deploying a native Ceph cluster using NVMe partition 3
- Creating a replicated block pool with 3 replicas
- Setting up RBD StorageClass as the default
- Validating the deployment with test PVCs
- Providing cleanup and uninstall capabilities

## Files

- `install.yaml` - Main Ansible playbook for Ceph/Rook deployment
- `uninstall.yaml` - Playbook for complete cluster removal
- `hosts.yaml` - Inventory file with target hosts
- `install.sh` - Convenience script to deploy the cluster
- `uninstall.sh` - Convenience script to remove the cluster
- `README.md` - This documentation file

## Prerequisites

### Infrastructure Requirements

- **K3s cluster** - Must be running and accessible
- **Partitioned NVMe drives** - Run the `nvme-partitioning` playbook first
- **Available partition** - `/dev/nvme0n1p3` should be clean and unused
- **Network connectivity** - All nodes must be able to communicate
- **Sufficient resources** - At least 2GB RAM and 2 CPU cores per node recommended

### Software Requirements

- Ansible installed on the control machine
- Helm installed on the bootstrap master
- kubectl access to the K3s cluster
- SSH access to all target hosts
- Sudo privileges on target hosts

### Node Configuration

The playbook expects these node roles:
- **bootstrapMaster** - Primary control plane node (blade001)
- **masters** - Additional control plane nodes (blade002, blade003)
- **workers** - Worker nodes (blade004, blade005)

## Configuration

### Hosts Configuration

Edit `hosts.yaml` to match your environment:

```yaml
all:
  children:
    bootstrapMaster:
      hosts:
        blade001:
          ansible_host: blade001
    masters:
      hosts:
        blade002:
          ansible_host: blade002
        blade003:
          ansible_host: blade003
    workers:
      hosts:
        blade004:
          ansible_host: blade004
        blade005:
          ansible_host: blade005
  vars:
    ansible_user: oleksiyp
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    ansible_python_interpreter: /usr/bin/python3
```

### Variables

The playbook uses these variables:

- `ceph_partition: "/dev/nvme0n1p3"` - NVMe partition for Ceph OSDs
- Ceph version: `quay.io/ceph/ceph:v19.2.2`
- Monitor count: 3 (for high availability)
- Manager count: 2 (for redundancy)
- Replication factor: 3 (for data safety)

## Deployment

### Method 1: Using the convenience script

```bash
./install.sh
```

### Method 2: Direct ansible-playbook command

```bash
ansible-playbook -i hosts.yaml install.yaml -v
```

## What the Playbook Does

### Phase 1: Rook Operator Installation
1. **Adds Helm repository** - Configures access to Rook charts
2. **Installs Rook operator** - Deploys the operator with CRDs
3. **Waits for readiness** - Ensures operator is available

### Phase 2: Storage Device Preparation
1. **Verifies partitions** - Checks that Ceph partitions exist
2. **Validates cleanliness** - Ensures partitions are ready for Ceph
3. **Shows status** - Displays partition information

### Phase 3: Ceph Cluster Deployment
1. **Creates CephCluster** - Deploys native Ceph cluster
2. **Configures OSDs** - Sets up one OSD per node using NVMe partition
3. **Enables dashboard** - Configures web management interface
4. **Waits for readiness** - Ensures cluster is operational

### Phase 4: Storage Configuration
1. **Creates block pool** - Sets up replicated pool with 3 replicas
2. **Configures StorageClass** - Creates and sets RBD as default
3. **Removes old default** - Disables local-path as default
4. **Validates setup** - Tests with temporary PVC

### Phase 5: Verification
1. **Tests integration** - Creates and validates test PVC
2. **Checks components** - Verifies all services are running
3. **Displays summary** - Shows cluster configuration
4. **Cleans up** - Removes test resources

## Cluster Configuration

### Ceph Cluster Specs

- **Monitors**: 3 (distributed across control plane nodes)
- **Managers**: 2 (for high availability)
- **OSDs**: 5 (one per node using NVMe partition 3)
- **Dashboard**: Enabled on port 8443 with SSL
- **Replication**: 3-way replication for data safety
- **Failure domain**: Host-based (survives single node failure)

### Storage Classes

After deployment:
- **ceph-rbd**: Default StorageClass for new PVCs
- **local-path**: Available but not default

### Features Enabled

- **Auto-scaling**: PG autoscaler enabled
- **Monitoring**: Basic monitoring enabled
- **Log collection**: Daily log rotation
- **Volume expansion**: Supported
- **Crash collection**: Enabled for debugging

## Management

### Cluster Status

```bash
# Check overall cluster status
kubectl get cephcluster -n rook-ceph

# Check Ceph health
kubectl exec -n rook-ceph deployment/rook-ceph-tools -- ceph status

# Check OSD status
kubectl get pods -n rook-ceph -l app=rook-ceph-osd

# Check storage classes
kubectl get storageclass
```

### Dashboard Access

```bash
# Get dashboard service
kubectl get svc -n rook-ceph rook-ceph-mgr-dashboard

# Port forward to access dashboard
kubectl port-forward -n rook-ceph svc/rook-ceph-mgr-dashboard 8443:8443
```

### Storage Usage

```bash
# Check storage capacity
kubectl exec -n rook-ceph deployment/rook-ceph-tools -- ceph df

# Check pool status
kubectl get cephblockpool -n rook-ceph

# List PVCs using Ceph
kubectl get pvc --all-namespaces -o wide | grep ceph-rbd
```

## Troubleshooting

### Common Issues

1. **OSDs not starting**
   - Check partition availability: `lsblk /dev/nvme0n1p3`
   - Verify partition is clean: `blkid /dev/nvme0n1p3`
   - Check node resources: `kubectl top nodes`

2. **Cluster not ready**
   - Check operator logs: `kubectl logs -n rook-ceph deployment/rook-ceph-operator`
   - Verify network connectivity between nodes
   - Check for sufficient disk space

3. **PVCs stuck pending**
   - Check StorageClass: `kubectl get storageclass ceph-rbd`
   - Verify Ceph health: `kubectl exec -n rook-ceph deployment/rook-ceph-tools -- ceph health`
   - Check CSI driver: `kubectl get pods -n rook-ceph -l app=csi-rbdplugin`

### Debug Commands

```bash
# Check all Rook/Ceph pods
kubectl get pods -n rook-ceph

# Check operator logs
kubectl logs -n rook-ceph deployment/rook-ceph-operator

# Check Ceph cluster events
kubectl get events -n rook-ceph --sort-by=.metadata.creationTimestamp

# Access Ceph tools
kubectl exec -it -n rook-ceph deployment/rook-ceph-tools -- bash
```

## Uninstallation

### Complete Removal

To completely remove the Ceph cluster and clean up storage:

```bash
# Using convenience script
./uninstall.sh

# Or directly with ansible
ansible-playbook -i hosts.yaml uninstall.yaml -v
```

### What Uninstall Does

1. **Deletes all PVCs** - Removes all persistent volume claims using Ceph
2. **Removes StorageClass** - Deletes ceph-rbd StorageClass
3. **Deletes pools** - Removes CephBlockPool resources
4. **Removes cluster** - Deletes CephCluster and waits for cleanup
5. **Uninstalls operator** - Removes Rook operator via Helm
6. **Cleans storage** - Wipes partitions and removes data directories
7. **Restores defaults** - Sets local-path back as default StorageClass

⚠️ **Warning**: Uninstallation will permanently delete all data stored in Ceph!

## Performance Tuning

### OSD Configuration

For better performance, consider:
- Increasing `databaseSizeMB` and `walSizeMB` for larger workloads
- Using `osdsPerDevice: "2"` for high-performance NVMe drives
- Enabling compression for space efficiency

### Pool Configuration

For different workload patterns:
- Adjust replica count based on availability vs. capacity needs
- Create separate pools for different performance requirements
- Configure different failure domains for larger clusters

## Security

### Network Security

- Ceph traffic is encrypted by default in newer versions
- Dashboard uses SSL certificates
- RBAC is enforced for all operations

### Access Control

- StorageClass access controlled via Kubernetes RBAC
- Ceph authentication handled automatically by Rook
- Dashboard access requires port forwarding or ingress setup

## Backup and Recovery

### Data Protection

- 3-way replication protects against single node failures
- Snapshots can be created using VolumeSnapshot resources
- Consider external backup solutions for disaster recovery

### Cluster Recovery

- Monitors can be rebuilt from remaining replicas
- OSDs can be replaced by running the playbook again
- Complete cluster rebuild possible with clean storage devices

## Integration Examples

### Creating Persistent Volumes

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
  storageClassName: ceph-rbd
```

### Volume Snapshots

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: my-app-snapshot
spec:
  volumeSnapshotClassName: ceph-rbd
  source:
    persistentVolumeClaimName: my-app-storage
```

## Monitoring Integration

The cluster can be integrated with monitoring systems:
- Prometheus metrics available via Ceph MGR
- Grafana dashboards for visualization
- Alert manager for notifications

## Version Compatibility

- **Rook Operator**: Latest stable release
- **Ceph**: v19.2.2 (Squid release)
- **Kubernetes**: Compatible with K3s v1.25+
- **Helm**: v3.x required

## Support and Resources

- [Rook Documentation](https://rook.io/docs/rook/latest/)
- [Ceph Documentation](https://docs.ceph.com/)
- [Kubernetes Storage](https://kubernetes.io/docs/concepts/storage/)

This playbook provides a production-ready Ceph storage solution for your K3s cluster with comprehensive management and troubleshooting capabilities.
