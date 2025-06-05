# Ceph NVMe Disk Setup Guide

This guide explains how to use the enhanced Ceph install playbook to prepare a full NVMe disk for Ceph OSD usage when booting from microSD.

## Configuration Overview

The playbook has been enhanced with the following capabilities:
- Automatic detection and preparation of NVMe disks for Ceph OSDs
- Safety checks to prevent accidental data loss
- Configurable variables for different scenarios
- Support for both LVM-based and raw device OSDs

## Configuration Variables

Edit the playbook or use extra vars to configure:

```yaml
vars:
  ceph_release: reef
  nvme_device: "/dev/nvme0n1"        # Primary NVMe device to use
  force_disk_wipe: false             # Set to true to force wipe even if mounted
  skip_disk_preparation: false       # Set to true to skip disk prep if already done
```

## Usage Scenarios

### 1. First Time Setup (Fresh NVMe Disk)
```bash
cd /home/oleksiyp/dev/basic-infra/ansible/ceph
ansible-playbook -i hosts.yaml install.yaml
```

### 2. Force Wipe Existing Data
```bash
ansible-playbook -i hosts.yaml install.yaml -e "force_disk_wipe=true"
```

### 3. Skip Disk Preparation (Already Done)
```bash
ansible-playbook -i hosts.yaml install.yaml -e "skip_disk_preparation=true"
```

### 4. Use Different NVMe Device
```bash
ansible-playbook -i hosts.yaml install.yaml -e "nvme_device=/dev/nvme1n1"
```

## What the Playbook Does

### Disk Preparation Phase:
1. **Safety Checks**: Verifies NVMe device exists and isn't system disk
2. **Device Detection**: Shows current partition layout
3. **Unmounting**: Safely unmounts any mounted partitions
4. **Cleanup**: Wipes filesystem signatures and LVM metadata
5. **Partitioning**: Creates clean GPT partition table
6. **Ceph Volume Prep**: Uses `ceph-volume lvm prepare` to prepare the disk

### OSD Creation Phase:
1. **Bootstrap Ceph**: Sets up the cluster on blade001
2. **Device Discovery**: Lists available devices for OSDs
3. **LVM Activation**: Activates any prepared LVM volumes
4. **OSD Creation**: Creates OSDs from prepared devices
5. **Verification**: Shows OSD tree and cluster status

## Expected Disk Layout

### Before (Boot from microSD):
```
/dev/mmcblk0p1  -> /boot/firmware (boot partition)
/dev/mmcblk0p2  -> / (root filesystem)
/dev/nvme0n1    -> [FULL DISK FOR CEPH]
```

### After Ceph Setup:
```
/dev/mmcblk0p1  -> /boot/firmware 
/dev/mmcblk0p2  -> /
/dev/nvme0n1    -> Ceph OSD (managed by LVM)
```

## Safety Features

1. **Mount Detection**: Prevents wiping if partitions are mounted (unless forced)
2. **Partition Listing**: Shows current partitions before making changes
3. **Force Flag**: Requires explicit confirmation to wipe existing data
4. **Skip Option**: Allows bypassing disk prep if already done

## Troubleshooting

### Device Not Found
```bash
# Check available NVMe devices
lsblk | grep nvme
# Update nvme_device variable accordingly
```

### Disk Already in Use
```bash
# Check current Ceph volumes
ceph-volume lvm list
# Use skip_disk_preparation=true if already prepared
```

### Manual Cleanup
```bash
# If you need to manually clean up
sudo ceph-volume lvm zap /dev/nvme0n1 --destroy
sudo wipefs -af /dev/nvme0n1
```

## Verification Commands

After running the playbook:

```bash
# Check Ceph cluster status
ceph status

# List OSDs
ceph osd tree

# Check OSD usage
ceph df

# List Ceph volumes
ceph-volume lvm list
```

## Current Host Configuration

With only `blade001` active in your `hosts.yaml`:
- Cluster will be single-node initially
- Can add more nodes later by updating hosts.yaml
- Single OSD will provide basic functionality for testing

## Next Steps

1. Run the enhanced playbook on blade001
2. Verify Ceph cluster is healthy
3. Add additional blades to otherHosts section when ready
4. Scale out the cluster with more OSDs
