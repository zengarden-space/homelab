#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Uninstalling restrictive-proxy from all nodes..."
ansible-playbook -i hosts.yaml uninstall.yaml

echo ""
echo "Uninstallation complete!"

