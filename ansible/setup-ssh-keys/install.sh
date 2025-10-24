#!/bin/bash
# SSH Setup Installation Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="$SCRIPT_DIR/hosts.yaml"
PLAYBOOK_FILE="$SCRIPT_DIR/install.yaml"

echo "Setting up seamless SSH access between blade001-blade005..."

# Check if files exist
if [[ ! -f "$HOSTS_FILE" ]]; then
    echo "Error: hosts.yaml not found at $HOSTS_FILE"
    exit 1
fi

if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    echo "Error: install.yaml not found at $PLAYBOOK_FILE"
    exit 1
fi

# Run the playbook
echo "Running Ansible playbook to setup SSH keys..."
ansible-playbook -i "$HOSTS_FILE" "$PLAYBOOK_FILE" "$@"

echo "SSH setup completed!"
echo ""
echo "You can now test SSH connectivity manually:"
echo "  ssh blade002 hostname"
echo "  ssh blade003 hostname"
echo "  ssh blade004 hostname"
echo "  ssh blade005 hostname"
