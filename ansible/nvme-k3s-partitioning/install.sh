#!/bin/bash

# Script to format NVMe drive for K3s using Ansible
# This script will format the entire /dev/nvme0n1 device as ext4 and mount it at /var/lib/rancher/k3s

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

echo "Starting NVMe K3s partitioning..."
echo "This will format /dev/nvme0n1 as ext4 and mount it at /var/lib/rancher/k3s"
echo ""

# Run the playbook
ansible-playbook -i "$HOSTS_FILE" "$PLAYBOOK_FILE" -v

echo ""
echo "NVMe K3s partitioning completed successfully!"
echo "The /dev/nvme0n1 device has been formatted and mounted at /var/lib/rancher/k3s"
