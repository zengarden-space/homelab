# NVMe K3s Partitioning

This Ansible playbook formats the entire `/dev/nvme0n1` device as ext4 and mounts it at `/var/lib/rancher/k3s` for K3s data storage.

## Overview

Unlike the more complex partitioning setup, this playbook:

- Formats the entire NVMe device as a single ext4 filesystem
- Mounts it at `/var/lib/rancher/k3s`
- Adds the mount to `/etc/fstab` for persistence
- Provides a simple, dedicated storage solution for K3s

## Files

- `install.yaml` - Ansible playbook for NVMe formatting and mounting
- `hosts.yaml` - Inventory file with target hosts
- `install.sh` - Convenience script to run the playbook
- `README.md` - This documentation file

## Prerequisites

- Ansible installed on the control machine
- SSH access to target hosts
- Target hosts should have NVMe device at `/dev/nvme0n1`
- Sudo privileges on target hosts

## Configuration

### Hosts Configuration

Edit `hosts.yaml` to match your environment:

```yaml
all:
  children:
    masters:
      hosts:
        master1:
          ansible_host: 192.168.1.10
        master2:
          ansible_host: 192.168.1.11
        master3:
          ansible_host: 192.168.1.12
  vars:
    ansible_user: admin
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

### Variables

The playbook uses these variables (defined in `install.yaml`):

- `nvme_device: "/dev/nvme0n1"` - The NVMe device to format
- `k3s_mount_point: "/var/lib/rancher/k3s"` - Where to mount the device

## Usage

### Method 1: Using the convenience script

```bash
./install.sh
```

### Method 2: Direct ansible-playbook command

```bash
ansible-playbook -i hosts.yaml install.yaml -v
```

## What the playbook does

1. **Stops K3s service** - Ensures K3s is not running during the operation
2. **Unmounts existing mount** - Safely unmounts any existing mount at the target path
3. **Cleans mount directory** - Removes any existing files from the mount point
4. **Removes LVM volumes** - Cleans up any existing LVM configurations on the NVMe device
5. **Wipes the device** - Completely wipes the NVMe device including filesystem signatures
6. **Formats as ext4** - Creates a single ext4 filesystem on the entire device
7. **Creates mount point** - Ensures the mount directory exists
8. **Mounts the device** - Mounts the formatted device at `/var/lib/rancher/k3s`
9. **Updates fstab** - Adds entry to `/etc/fstab` for persistent mounting
10. **Sets permissions** - Ensures correct ownership and permissions
11. **Displays results** - Shows filesystem and mount information

## Warning

⚠️ **This playbook will completely wipe the NVMe device and destroy all existing data on it!**

Make sure you have backups of any important data before running this playbook.

## After Running

After successful completion:

- The entire `/dev/nvme0n1` device will be formatted as ext4
- It will be mounted at `/var/lib/rancher/k3s`
- The mount will persist across reboots via `/etc/fstab`
- K3s can now be installed and will use this dedicated storage

## Troubleshooting

If the playbook fails:

1. Check that the NVMe device exists: `lsblk | grep nvme0n1`
2. Ensure no processes are using the device: `lsof /dev/nvme0n1`
3. Verify SSH connectivity to target hosts
4. Check Ansible inventory configuration
5. Review the playbook output for specific error messages

## Verification

After running, verify the setup:

```bash
# Check if device is mounted
df -h /var/lib/rancher/k3s

# Check mount in fstab
grep k3s /etc/fstab

# View block device information
lsblk /dev/nvme0n1
```
