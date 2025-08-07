#!/bin/bash

# Script to uninstall Ceph/Rook cluster using Ansible
# This script will cleanly remove the Ceph cluster and Rook operator

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="${SCRIPT_DIR}/hosts.yaml"
UNINSTALL_PLAYBOOK="${SCRIPT_DIR}/uninstall.yaml"

# Check if required files exist
if [[ ! -f "$HOSTS_FILE" ]]; then
    echo "Error: hosts.yaml not found at $HOSTS_FILE"
    exit 1
fi

if [[ ! -f "$UNINSTALL_PLAYBOOK" ]]; then
    echo "Error: uninstall.yaml not found at $UNINSTALL_PLAYBOOK"
    exit 1
fi

# Check if ansible is installed
if ! command -v ansible-playbook &> /dev/null; then
    echo "Error: ansible-playbook is not installed"
    echo "Please install Ansible first: sudo apt install ansible"
    exit 1
fi

echo "⚠️  WARNING: This will completely remove the Ceph cluster and all data!"
echo ""
echo "This will:"
echo "  • Delete all PVCs and PVs using Ceph storage"
echo "  • Remove the Ceph cluster and all OSDs"
echo "  • Uninstall the Rook operator"
echo "  • Clean up storage devices"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Starting Ceph/Rook cluster uninstallation..."

# Run the uninstall playbook
ansible-playbook -i "$HOSTS_FILE" "$UNINSTALL_PLAYBOOK" -v

echo ""
echo "Ceph/Rook cluster uninstallation completed!"
echo "Storage devices have been cleaned and are ready for reuse."
