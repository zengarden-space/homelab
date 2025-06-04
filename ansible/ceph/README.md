
# Ceph Cluster Installation on Raspberry Pi

This Ansible playbook installs and configures a Ceph cluster on Raspberry Pi machines using cephadm.

## Prerequisites

- Raspberry Pi 4 (minimum 4GB RAM recommended)
- Ubuntu 20.04+ or Debian 11+ on all nodes
- At least one additional storage device per node (USB drive, SSD, etc.) for OSDs
- SSH access configured for all nodes
- Internet connectivity on all nodes

## Features

- Installs latest stable Ceph (Reef release) via official Ceph APT repositories
- Configures Docker as container runtime
- Sets up NTP synchronization
- Bootstraps Ceph cluster with dashboard
- Automatically discovers and configures OSDs
- Deploys monitors and managers across all nodes

## Installation

### 1. Install to all hosts:
```bash
bash install.sh
```

### 2. Manual installation:
```bash
ansible-playbook -i hosts.yaml install.yaml
```

## Configuration

### Dashboard Access
After installation, the Ceph dashboard will be available at:
- URL: `https://<bootstrap-master-ip>:8443`
- Username: `admin`
- Password: `admin123`

### Default Configuration
- **Ceph Release**: Reef (latest stable)
- **Container Runtime**: Docker
- **Monitor Placement**: All nodes
- **Manager Placement**: First 3 nodes
- **OSD Placement**: Automatic discovery on available devices

## Storage Requirements

The playbook will automatically detect available storage devices for OSDs. Ensure you have:
- Additional block devices (not the root filesystem device)
- At least 5GB free space per OSD device
- Preferably SSD or fast USB 3.0 storage for better performance

## Cluster Operations

### Check cluster status:
```bash
# On any cluster node
sudo ceph status
sudo ceph health
sudo ceph df
```

### View cluster topology:
```bash
sudo ceph osd tree
sudo ceph mon stat
sudo ceph mgr stat
```

### Add OSD manually:
```bash
sudo ceph orch device ls  # List available devices
sudo ceph orch daemon add osd <hostname>:<device>  # Add specific device
```

## Uninstallation

### Complete removal (WARNING: This will destroy all data):
```bash
bash uninstall.sh
```

### Manual uninstall:
```bash
ansible-playbook -i hosts.yaml uninstall.yaml
```

### Clean disk partitions (optional):
```bash
ansible-playbook -i hosts.yaml uninstall.yaml -e cleanup_disks=true
```

## Troubleshooting

### Common Issues

1. **Bootstrap fails with IP binding error**
   - Ensure the specified IP address is correct
   - Check firewall settings (ports 3300, 6789, 6800-7300)

2. **No OSDs created**
   - Verify additional storage devices are available
   - Check device permissions and mounting status
   - Use `sudo ceph orch device ls` to see available devices

3. **Cluster health warnings**
   - Check `sudo ceph health detail` for specific issues
   - Verify all nodes can communicate with each other
   - Ensure NTP is synchronized across all nodes

4. **Container failures**
   - Check Docker status: `sudo systemctl status docker`
   - Verify container logs: `sudo docker logs <container-name>`

### Log Locations
- Ceph logs: `/var/log/ceph/`
- Container logs: `sudo docker logs <container-name>`
- System logs: `journalctl -u ceph*`

### Performance Tuning

For Raspberry Pi clusters:
- Use fast storage devices (SSD over USB 3.0)
- Ensure adequate cooling
- Monitor CPU and memory usage
- Consider reducing replica count for small clusters:
  ```bash
  sudo ceph osd pool set <pool-name> size 2
  sudo ceph osd pool set <pool-name> min_size 1
  ```

## Security Notes

- Default dashboard password is `admin123` - change it immediately
- Ensure proper network segmentation
- Configure firewall rules appropriately
- Consider enabling Ceph authentication features for production use

## Support

For issues specific to this playbook, check:
1. Ansible output for detailed error messages
2. Ceph cluster status and health
3. Docker container status and logs
4. Network connectivity between nodes
