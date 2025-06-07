# Ceph Additional Services Configuration

This guide covers the configuration and usage of additional Ceph services installed by the main `install.yaml` playbook.

## Services Overview

The playbook automatically installs and configures the following additional services:

### Object Gateway (RGW) - S3/Swift API
- **Purpose**: Provides S3 and Swift compatible object storage APIs
- **Placement**: First 3 hosts for high availability
- **Default Port**: 80 (HTTP)
- **Service Name**: `rgw.default`

### NFS Service - POSIX File Access
- **Purpose**: Provides NFS exports for POSIX file system access
- **Placement**: First 2 hosts for redundancy
- **Service Name**: `nfs.nfs-cluster`

### SMB Service - Windows File Sharing
- **Purpose**: Provides Samba/CIFS shares for Windows compatibility
- **Placement**: First 2 hosts for redundancy
- **Service Name**: `smb.smb-cluster`

## Post-Installation Configuration

### Object Gateway (RGW) Setup

#### 1. Create RGW User for S3 Access
```bash
# Create a user
cephadm shell -- radosgw-admin user create --uid=myuser --display-name="My User"

# Create access keys
cephadm shell -- radosgw-admin key create --uid=myuser --key-type=s3 --gen-access-key --gen-secret

# List users
cephadm shell -- radosgw-admin user list
```

#### 2. Test S3 Access
```bash
# Install s3cmd for testing
apt install s3cmd

# Configure s3cmd with the generated keys
s3cmd --configure

# Test connection
s3cmd ls
```

#### 3. Create S3 Bucket
```bash
# Using s3cmd
s3cmd mb s3://test-bucket

# Using AWS CLI
aws s3 mb s3://test-bucket --endpoint-url http://<rgw-host>:80
```

### NFS Service Setup

#### 1. Create CephFS for NFS
```bash
# Create a filesystem (if not already exists)
cephadm shell -- ceph fs new myfs myfs-metadata myfs-data

# Enable NFS module
cephadm shell -- ceph mgr module enable nfs
```

#### 2. Create NFS Export
```bash
# Create NFS export
cephadm shell -- ceph nfs export create cephfs nfs-cluster /export myfs --path=/

# List exports
cephadm shell -- ceph nfs export ls nfs-cluster
```

#### 3. Mount NFS Share on Client
```bash
# On client machine
sudo mkdir /mnt/ceph-nfs
sudo mount -t nfs <nfs-host>:/export /mnt/ceph-nfs
```

### SMB Service Setup

#### 1. Configure SMB Share
```bash
# Enable SMB module
cephadm shell -- ceph mgr module enable smb

# Create SMB share configuration
cephadm shell -- ceph smb share create smb-cluster myshare myfs /share
```

#### 2. Create SMB User
```bash
# Create SMB user
cephadm shell -- ceph smb user create smb-cluster smbuser password123
```

#### 3. Mount SMB Share on Windows/Linux
```bash
# On Linux client
sudo mkdir /mnt/ceph-smb
sudo mount -t cifs //<smb-host>/myshare /mnt/ceph-smb -o username=smbuser,password=password123

# On Windows (in Command Prompt)
net use Z: \\<smb-host>\myshare /user:smbuser password123
```

## Service Management

### Check Service Status
```bash
# List all orchestrator services
cephadm shell -- ceph orch ls

# Check specific service status
cephadm shell -- ceph orch ps --service_name rgw.default
cephadm shell -- ceph orch ps --service_name nfs.nfs-cluster
cephadm shell -- ceph orch ps --service_name smb.smb-cluster
```

### Scale Services
```bash
# Scale RGW to more hosts
cephadm shell -- ceph orch apply rgw default --placement="5"

# Scale NFS to more hosts
cephadm shell -- ceph orch apply nfs nfs-cluster --placement="3"
```

### Remove Services
```bash
# Remove RGW service
cephadm shell -- ceph orch rm rgw.default

# Remove NFS service
cephadm shell -- ceph orch rm nfs.nfs-cluster

# Remove SMB service
cephadm shell -- ceph orch rm smb.smb-cluster
```

## Storage Requirements

Before using these services, ensure you have:

1. **OSDs**: Add storage devices using the `add-storage.yaml` playbook
2. **Pools**: Create pools for object storage, metadata, and data
3. **CephFS**: For NFS and SMB services

### Create Required Pools
```bash
# Create pools for RGW
cephadm shell -- ceph osd pool create .rgw.root 32
cephadm shell -- ceph osd pool create default.rgw.control 32
cephadm shell -- ceph osd pool create default.rgw.meta 32
cephadm shell -- ceph osd pool create default.rgw.log 32
cephadm shell -- ceph osd pool create default.rgw.buckets.index 32
cephadm shell -- ceph osd pool create default.rgw.buckets.data 128

# Create pools for CephFS (NFS/SMB)
cephadm shell -- ceph osd pool create myfs-metadata 32
cephadm shell -- ceph osd pool create myfs-data 128
```

## Security Considerations

### RGW Security
- Use HTTPS in production (configure SSL certificates)
- Implement proper access keys rotation
- Configure bucket policies and IAM roles

### NFS Security
- Configure proper export restrictions
- Use Kerberos authentication for secure environments
- Implement network-level access controls

### SMB Security
- Use strong passwords for SMB users
- Configure domain authentication if possible
- Implement share-level permissions

## Monitoring and Logs

### Service Logs
```bash
# RGW logs
cephadm shell -- ceph log last 50 | grep rgw

# NFS logs
journalctl -u ceph-*nfs* -f

# SMB logs
journalctl -u ceph-*smb* -f
```

### Performance Monitoring
```bash
# Check RGW performance
cephadm shell -- ceph orch ps --service_name rgw.default

# Monitor NFS performance
cephadm shell -- ceph fs status myfs

# General cluster performance
cephadm shell -- ceph status
cephadm shell -- ceph df
```

## Troubleshooting

### Common Issues

1. **Services not starting**: Check host resources and network connectivity
2. **Authentication failures**: Verify user credentials and permissions
3. **Connection timeouts**: Check firewall rules and service bindings
4. **Storage errors**: Ensure sufficient OSDs and healthy pools

### Debug Commands
```bash
# Debug RGW
cephadm shell -- radosgw-admin user info --uid=myuser

# Debug NFS
cephadm shell -- ceph nfs export get nfs-cluster /export

# Debug SMB
cephadm shell -- ceph smb share ls smb-cluster
```

For more detailed troubleshooting, refer to the official Ceph documentation for each service.
