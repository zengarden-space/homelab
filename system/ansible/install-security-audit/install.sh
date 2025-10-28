#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Installing security audit script to all blade nodes..."
ansible-playbook -v -i hosts.yaml install.yaml
echo "Installation complete!"
