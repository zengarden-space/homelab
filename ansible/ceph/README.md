# Ceph Cluster Installation

This runbook installs a Ceph cluster on all blade servers with the necessary prerequisites. It focuses only on cluster setup without storage device management.

## Features

- **Idempotent Installation**: Safe to run multiple times without side effects
- **Smart State Detection**: Automatically detects existing cluster components
- **Incremental Setup**: Can add new hosts to existing clusters
- **Robust Error Handling**: Handles various cluster states gracefully
- Installs Docker and required system packages
- Sets up Ceph repository and packages
- Bootstraps Ceph cluster on the first node
- Adds all other nodes to the cluster
- Configures monitors and managers with intelligent placement
- Provides dashboard access for cluster management

## Idempotency Features

The playbook is designed to be completely idempotent, meaning you can run it multiple times safely:

- **Cluster Detection**: Checks if Ceph cluster is already running before bootstrapping
- **Package Management**: Only installs packages if they're not already present
- **Host Management**: Only adds hosts that aren't already in the cluster
- **Service Configuration**: Only updates service placement when changes are needed
- **SSH Key Distribution**: Only distributes keys when necessary
- **State Preservation**: Maintains existing cluster configuration when appropriate

## Requirements

- Ansible installed on the control machine
- SSH access to all blade servers
- Sudo privileges on the blade servers
- Ubuntu 20.04+ on all blade servers

## Usage

### Standard Installation

1. Edit the `hosts.yaml` file to include your blade servers.

2. Run the installation:
   ```bash
   bash install.sh
   ```

3. Follow the prompts and enter your sudo password when requested.

### Testing Idempotency

To verify the playbook doesn't make unnecessary changes:
```bash
bash test-idempotent.sh
```

### Check Mode (Dry Run)

To see what changes would be made without applying them:
```bash
ansible-playbook -i hosts.yaml install.yaml --check
```

## Post-Installation

After successful installation, the playbook provides comprehensive status information:

1. **Cluster Dashboard Access:**
   - URL: `https://<bootstrap-master-ip>:8443`
   - Username: `admin`
   - Password: `admin123`

2. **Installation Summary:**
   - Total hosts in cluster
   - Service placement details (monitors, managers)
   - Health status and any warnings
   - Re-run instructions

3. **Next Steps:**
   - Use the `ceph-volumes` runbook to add storage devices (includes NVMe enablement)
   - Create pools and configure storage classes
   - Configure authentication and users as needed

**Note:** NVMe support enablement has been moved to the `ceph-volumes` runbook. This separation allows you to install the Ceph cluster first, then handle storage device preparation (including NVMe enablement and verification) in a separate step.

## Enhanced Output

The playbook provides detailed output including:
- **State Detection**: Shows whether cluster is new or existing
- **Host Management**: Reports which hosts are added vs already present
- **Service Updates**: Shows when monitor/manager placement is updated
- **Health Monitoring**: Displays cluster health and detailed warnings
- **Configuration Summary**: Complete overview of final cluster state

## Configuration

The installation uses the following defaults:
- Ceph release: `reef`
- Dashboard user: `admin`
- Dashboard password: `admin123`
- Monitor placement: All hosts
- Manager placement: First 3 hosts

## Troubleshooting

1. **Check cluster status:**
   ```bash
   ceph status
   ```

2. **Check cluster health:**
   ```bash
   ceph health detail
   ```

3. **View logs:**
   ```bash
   journalctl -u ceph-mon@<hostname>
   journalctl -u ceph-mgr@<hostname>
   ```

## Uninstallation

To completely remove Ceph from all hosts:
```bash
bash uninstall.sh
```

**Warning:** This will destroy the entire cluster. Storage devices will need to be cleaned separately using the `ceph-volumes` runbook.
