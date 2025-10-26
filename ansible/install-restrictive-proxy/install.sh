#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

# Check if .env exists
if [ ! -f .env ]; then
    echo "Error: .env not found"
    echo "Please copy .env.template to .env and fill in the values"
    exit 1
fi

# Source .env file and export variables
set -a
source .env
set +a

echo "Installing restrictive-proxy on all nodes..."
ansible-playbook -i hosts.yaml \
  -e "domain=$DOMAIN" \
  -e "mikrotik_password=$MIKROTIK_ADMIN_PASSWORD" \
  install.yaml

echo ""
echo "Installation complete!"
echo ""
echo "To check service status:"
echo "  ansible proxy_nodes -i hosts.yaml -b -m shell -a 'systemctl status restrictive-proxy'"
echo ""
echo "To view logs:"
echo "  ansible proxy_nodes -i hosts.yaml -b -m shell -a 'journalctl -u restrictive-proxy -n 50 --no-pager'"
