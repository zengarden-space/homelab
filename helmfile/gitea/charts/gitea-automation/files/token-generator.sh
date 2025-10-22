#!/bin/sh
set -euo pipefail

echo "Waiting for Gitea pods to be ready..."
kubectl wait --for=condition=ready pod -l app=gitea -n gitea --timeout=300s
echo "Gitea pods are ready"

echo "Finding a running Gitea pod in gitea namespace..."
GITEA_POD=$(kubectl get pods -n gitea -l app=gitea -o jsonpath='{.items[0].metadata.name}')

if [ -z "$GITEA_POD" ]; then
  echo "Error: No Gitea pod found"
  exit 1
fi

# Check if secret already exists with correct scopes
echo "Checking if secret ${TOKEN_NAME} already exists..."
if kubectl get secret ${TOKEN_NAME} -n ${RELEASE_NAMESPACE} >/dev/null 2>&1; then
  echo "Secret ${TOKEN_NAME} exists. Checking scopes..."
  EXISTING_SCOPES=$(kubectl get secret ${TOKEN_NAME} -n ${RELEASE_NAMESPACE} -o jsonpath='{.data.scopes}' | base64 -d)
  EXISTING_USER=$(kubectl get secret ${TOKEN_NAME} -n ${RELEASE_NAMESPACE} -o jsonpath='{.data.user}' | base64 -d)
  EXISTING_TOKEN=$(kubectl get secret ${TOKEN_NAME} -n ${RELEASE_NAMESPACE} -o jsonpath='{.data.token}' | base64 -d)
  
  if [ "$EXISTING_SCOPES" = "${TOKEN_SCOPES}" ] && [ "$EXISTING_USER" = "${TOKEN_USER}" ] && [ -n "$EXISTING_TOKEN" ]; then
    echo "✅ Secret ${TOKEN_NAME} already exists with correct scopes and user. Skipping token generation."
    exit 0
  else
    echo "⚠️  Secret ${TOKEN_NAME} exists but has different scopes or user. Current: '$EXISTING_SCOPES' for user '$EXISTING_USER', Expected: '${TOKEN_SCOPES}' for user '${TOKEN_USER}'"
    echo "Deleting existing secret and regenerating token..."
    kubectl delete secret ${TOKEN_NAME} -n ${RELEASE_NAMESPACE}
  fi
else
  echo "Secret ${TOKEN_NAME} does not exist. Will create new token."
fi

# Execute gitea command inside gitea container to generate token
echo "Generating new access token..."
TOKEN=$(kubectl exec -n ${GITEA_NAMESPACE} $GITEA_POD -- \
  gitea admin user generate-access-token \
  --username ${TOKEN_USER} \
  --token-name ${TOKEN_NAME}-${TOKEN_SCOPES_HASH} \
  --scopes "${TOKEN_SCOPES}" \
  --raw)

if [ -z "$TOKEN" ]; then
  echo "❌ Failed to generate token"
  exit 1
fi

echo "✅ Token generated successfully. Creating secret..."

# Create the secret
kubectl create secret generic ${TOKEN_NAME} \
  --from-literal=token="$TOKEN" \
  --from-literal=scopes="${TOKEN_SCOPES}" \
  --from-literal=user="${TOKEN_USER}" \
  -n ${RELEASE_NAMESPACE}

echo "✅ Secret ${TOKEN_NAME} created successfully"
