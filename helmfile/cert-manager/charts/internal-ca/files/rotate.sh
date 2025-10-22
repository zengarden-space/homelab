#!/bin/sh

set -euo pipefail

# Setup from service account
pushd /var/run/secrets/kubernetes.io/serviceaccount

NAMESPACE=$(cat namespace)
TOKEN=$(cat token)
CACERT=$(pwd)/ca.crt
APISERVER=https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}

popd

# Function to make authenticated API calls
kube_api() {
    curl -s --fail \
        --cacert "$CACERT" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "$@"
}

# Function to extract JSON field value using sed/awk
json_extract() {
    local field="$1"
    sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# Function to extract base64 data field from secret JSON
extract_data_field() {
    local field="$1"
    sed -n "s/.*\"data\"[[:space:]]*:[[:space:]]*{.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# Get ca-root-tls secret
SECRET_JSON=$(kube_api "$APISERVER/api/v1/namespaces/$NAMESPACE/secrets/ca-root-tls")
CERT=$(echo "$SECRET_JSON" | extract_data_field "tls.crt")

# Get expiration date
EXPIRATION_DATE=$(echo "$CERT" | base64 -d | openssl x509 -noout -enddate | awk -F '=' '{print $2}' | date +%y%d%m%H%M%S -f -)

# Create new secret with expiration timestamp
cat <<EOF | kube_api -X POST "$APISERVER/api/v1/namespaces/$NAMESPACE/secrets" -d @-
{
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "ca-root-tls-$EXPIRATION_DATE",
    "labels": {
      "belongs": "ca-root"
    }
  },
  "data": {
    "ca.crt": "$CERT"
  }
}
EOF

echo -n > ca.crt

# Get all secrets with label belongs=ca-root
SECRETS_JSON=$(kube_api "$APISERVER/api/v1/namespaces/$NAMESPACE/secrets?labelSelector=belongs=ca-root")

# Extract secret names from the list
SECRET_NAMES=$(echo "$SECRETS_JSON" | grep -o '"name":"[^"]*"' | sed 's/"name":"\([^"]*\)"/\1/')

# Process each secret
for SECRET_NAME in $SECRET_NAMES; do
    # Get individual secret
    SECRET=$(kube_api "$APISERVER/api/v1/namespaces/$NAMESPACE/secrets/$SECRET_NAME")

    # Extract ca.crt field
    CERT_B64=$(echo "$SECRET" | extract_data_field "ca.crt")

    # Decode certificate
    echo "$CERT_B64" | base64 -d > one.crt

    echo -n "$SECRET_NAME expiration: "
    if cat one.crt | openssl x509 -noout -checkend 0; then
        cat one.crt >> ca.crt
    else
        # Delete expired secret
        kube_api -X DELETE "$APISERVER/api/v1/namespaces/$NAMESPACE/secrets/$SECRET_NAME"
    fi
done

echo "Trust roots PEM:"
cat ca.crt

# Create or update ConfigMap
# First check if it exists
if kube_api "$APISERVER/api/v1/namespaces/$NAMESPACE/configmaps/internal-ca-tls" >/dev/null 2>&1; then
    # Update existing ConfigMap
    cat <<EOF | kube_api -X PUT "$APISERVER/api/v1/namespaces/$NAMESPACE/configmaps/internal-ca-tls" -d @-
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "internal-ca-tls"
  },
  "data": {
    "ca.crt": "$(cat ca.crt | sed ':a;N;$!ba;s/\n/\\n/g')"
  }
}
EOF
else
    # Create new ConfigMap
    cat <<EOF | kube_api -X POST "$APISERVER/api/v1/namespaces/$NAMESPACE/configmaps" -d @-
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "internal-ca-tls"
  },
  "data": {
    "ca.crt": "$(cat ca.crt | sed ':a;N;$!ba;s/\n/\\n/g')"
  }
}
EOF
fi