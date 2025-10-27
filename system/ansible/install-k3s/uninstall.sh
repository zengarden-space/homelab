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

ansible-playbook -i hosts.yaml uninstall.yaml \
 -e "domain=$DOMAIN"