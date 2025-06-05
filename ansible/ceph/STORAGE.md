# Add Storage to Ceph Cluster

This playbook adds `/dev/nvme0` devices from all hosts as OSDs (Object Storage Daemons) to the existing Ceph cluster.

## Prerequisites

- Ceph cluster must be operational (use `install.yaml` first)
- `/dev/nvme0` device must exist on each host
- Device should be clean/wiped if previously used
- SSH access and sudo privileges on all hosts

## Features

- **Idempotent**: Safe to run multiple times, skips already added devices
- **Device Validation**: Checks if NVMe device exists before attempting to add
- **Duplicate Detection**: Verifies device isn't already part of the cluster
- **Status Reporting**: Shows detailed results for each host
- **Health Monitoring**: Displays cluster health after storage addition

## Usage

### Quick Start
```bash
bash add-storage.sh
```

### Manual Execution
```bash
ansible-playbook -i hosts.yaml add-storage.yaml --ask-become-pass
```

### Check Mode (Dry Run)
```bash
ansible-playbook -i hosts.yaml add-storage.yaml --check
```

## What It Does

1. **Cluster Validation**: Verifies Ceph cluster is operational
2. **Device Discovery**: Checks for `/dev/nvme0` on each host
3. **Duplicate Prevention**: Ensures device isn't already added to cluster
4. **OSD Creation**: Adds device as OSD using `ceph orch daemon add osd`
5. **Status Verification**: Shows final cluster and OSD status

## Expected Behavior

### First Run
- Adds `/dev/nvme0` from each host as new OSDs
- Creates OSD daemons automatically
- Updates cluster configuration

### Subsequent Runs (Idempotent)
- Detects already added devices
- Skips duplicate additions
- Reports current status

## Manual Device Preparation

If you need to wipe devices manually before adding:

```bash
# On each host, wipe the NVMe device
sudo wipefs -a /dev/nvme0

# Optionally, create a new partition table
sudo sgdisk --zap-all /dev/nvme0
```

## Verification

After running the playbook, verify the storage was added:

```bash
# Check OSD status
cephadm shell -- ceph osd status

# Check cluster status
cephadm shell -- ceph status

# List all OSDs
cephadm shell -- ceph osd ls

# Check cluster health
cephadm shell -- ceph health detail
```

## Troubleshooting

### Device Not Found
- Verify `/dev/nvme0` exists: `ls -la /dev/nvme*`
- Check if device is properly detected: `lsblk`

### Device Already in Use
- Check if device has existing partitions: `lsblk /dev/nvme0`
- Wipe device if needed: `wipefs -a /dev/nvme0`

### OSD Creation Failed
- Check Ceph logs: `cephadm shell -- ceph log last 20`
- Verify device permissions and accessibility
- Ensure sufficient disk space

## Expected Results

After successful completion:
- 5 new OSDs (one per host) 
- Cluster status shows OSDs as `up` and `in`
- Health should be `HEALTH_OK` or `HEALTH_WARN` (normal during rebalancing)
- Storage capacity increased in cluster

## Next Steps

1. **Wait for Rebalancing**: Allow cluster to distribute data across new OSDs
2. **Create Pools**: Create storage pools for applications
3. **Configure Storage Classes**: Set up Kubernetes storage classes
4. **Monitor Performance**: Verify cluster performance and health
