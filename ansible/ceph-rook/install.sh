#!/bin/bash

# Script to deploy Ceph/Rook cluster using Ansible
# This script requires an existing K3s cluster and partitioned NVMe drives

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="${SCRIPT_DIR}/hosts.yaml"
PLAYBOOK_FILE="${SCRIPT_DIR}/install.yaml"

# Check if required files exist
if [[ ! -f "$HOSTS_FILE" ]]; then
    echo "Error: hosts.yaml not found at $HOSTS_FILE"
    exit 1
fi

if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    echo "Error: install.yaml not found at $PLAYBOOK_FILE"
    exit 1
fi

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: ansible-playbook is not installed"
    echo "Please install Ansible first: sudo apt install ansible"
    exit 1
fi

echo "Starting Ceph/Rook cluster deployment..."
echo "This will deploy a native Ceph cluster using Rook operator on K3s"
echo ""
echo "Prerequisites:"
echo "  • K3s cluster must be running"
echo "  • NVMe drives must be partitioned (run nvme-partitioning playbook first)"
echo "  • Partition 3 (/dev/nvme0n1p3) should be available for Ceph"
echo ""

# Run the playbook
ansible-playbook -i "$HOSTS_FILE" "$PLAYBOOK_FILE" -v

echo ""
echo "Ceph/Rook cluster deployment completed successfully!"
echo "The cluster is now ready for persistent storage workloads."
