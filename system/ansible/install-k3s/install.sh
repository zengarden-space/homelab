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

ansible-playbook -v -i hosts.yaml install.yaml \
 -e "domain=$DOMAIN" \
 -e "google_oidc_client_id=$GOOGLE_OIDC_CLIENT_ID" \
 -e "google_oidc_client_secret=$GOOGLE_OIDC_CLIENT_SECRET" \
 -e "google_oidc_admin_email=$GOOGLE_OIDC_ADMIN_EMAIL"
