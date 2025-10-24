source .env
ansible-playbook -v -i hosts.yaml install.yaml \
 -e "google_oidc_client_id=$GOOGLE_OIDC_CLIENT_ID" \
 -e "google_oidc_client_secret=$GOOGLE_OIDC_CLIENT_SECRET" \
 -e "google_oidc_admin_email"="$GOOGLE_OIDC_ADMIN_EMAIL"
