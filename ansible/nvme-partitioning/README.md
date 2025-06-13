# NVMe Repartitioning for K3s etcd

This runbook repartitions NVMe drives on master nodes to create dedicated partitions for K3s etcd storage and Ceph storage.

## Overview

- **Target nodes**: blade001, blade002, blade003 (K3s master nodes)
- **NVMe device**: `/dev/nvme0n1` (931.5GB each)
- **Partitioning scheme**:
  - Partition 1: 10GiB for K3s etcd (`/var/lib/rancher/k3s`)
  - Partition 2: Remaining space (~921GiB) for Ceph OSDs

## Prerequisites

- All target nodes should be accessible via SSH
- K3s should be stopped before running (script handles this)
- Existing Ceph cluster should be uninstalled (separate runbook)

## What it does

1. **Cleanup**: Removes existing Ceph LVM volumes and stops K3s
2. **Wipe**: Completely wipes the NVMe device 
3. **Partition**: Creates GPT partition table with etcd and Ceph partitions
4. **Format**: Creates ext4 filesystem on etcd partition with label "etcd-data"
5. **Mount**: Mounts etcd partition at `/var/lib/rancher/k3s` with optimized options
6. **Configure**: Adds mount to fstab for persistence

## Usage

```bash
cd /home/oleksiyp/dev/zengarden/basic-infra/ansible/nvme-partition
./install.sh
```

## Safety

- **DESTRUCTIVE**: This operation completely wipes NVMe drives
- **IRREVERSIBLE**: All existing data on NVMe drives will be lost
- **CONFIRMATION**: Requires explicit "yes" confirmation
- **BACKUP**: Ensure you have backups of any important data

## Expected Result

After successful completion:
- `/dev/nvme0n1p1`: 10GiB etcd partition mounted at `/var/lib/rancher/k3s`
- `/dev/nvme0n1p2`: ~921GiB partition available for Ceph OSDs
- Optimized mount options for etcd performance (`noatime`)
- Proper filesystem labels for easy identification

## Next Steps

1. Modify K3s installation to use the new etcd location
2. Install K3s with updated configuration
3. Deploy Ceph cluster via Rook operator using the Ceph partition

## Troubleshooting

### Device busy errors
If you get "device busy" errors:
- Check for any running processes: `fuser -v /dev/nvme0n1`
- Ensure K3s and Ceph services are stopped
- Reboot if necessary

### Mount failures
If etcd partition fails to mount:
- Check filesystem: `fsck /dev/nvme0n1p1`
- Verify partition exists: `lsblk /dev/nvme0n1`
- Check fstab syntax: `mount -a`

### LVM cleanup issues
If Ceph LVM volumes persist:
- Manual cleanup: `vgremove -f <vg-name>`
- Physical volume cleanup: `pvremove -f /dev/nvme0n1`
