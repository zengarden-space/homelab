#!/bin/sh
set -eu

echo "=== Gitea Organization Creator Script ==="
echo "Creating organization: ${ORG_NAME}"

# Gitea API endpoint
GITEA_URL="http://${GITEA_SERVICE_NAME}.${GITEA_NAMESPACE}.svc.cluster.local:${GITEA_SERVICE_PORT}"
API_ENDPOINT="${GITEA_URL}/api/v1/orgs"

echo "Gitea URL: ${GITEA_URL}"
echo "API Endpoint: ${API_ENDPOINT}"

# Check if Gitea is accessible
echo "Checking Gitea connectivity..."
for i in {1..30}; do
    if curl -sf "${GITEA_URL}/api/healthz" > /dev/null 2>&1; then
        echo "✅ Gitea is accessible"
        break
    fi
    echo "⏳ Waiting for Gitea to be ready... (attempt $i/30)"
    sleep 10
done

# Check if Gitea is still not accessible
if ! curl -sf "${GITEA_URL}/api/healthz" > /dev/null 2>&1; then
    echo "❌ Error: Gitea is not accessible after 5 minutes"
    exit 1
fi

# Check if organization already exists
echo "Checking if organization '${ORG_NAME}' already exists..."
if curl -sf -H "Authorization: token ${GITEA_TOKEN}" "${API_ENDPOINT}/${ORG_NAME}" > /dev/null 2>&1; then
    echo "✅ Organization '${ORG_NAME}' already exists"
    echo "Getting organization details..."
    curl -s -H "Authorization: token ${GITEA_TOKEN}" "${API_ENDPOINT}/${ORG_NAME}"
    exit 0
fi

echo "Creating organization '${ORG_NAME}'..."

# Create organization payload
ORG_PAYLOAD=$(cat <<EOF
{
    "username": "${ORG_NAME}",
    "description": "${ORG_DESCRIPTION}",
    "website": "${ORG_WEBSITE}",
    "visibility": "${ORG_VISIBILITY}",
    "repo_admin_change_team_access": true
}
EOF
)

echo "Organization payload:"
echo "${ORG_PAYLOAD}"

# Create the organization
echo "Sending API request to create organization..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: token ${GITEA_TOKEN}" \
    -d "${ORG_PAYLOAD}" \
    "${API_ENDPOINT}")

# Extract HTTP status code
HTTP_CODE=$(echo "${RESPONSE}" | tail -n1)
RESPONSE_BODY=$(echo "${RESPONSE}" | head -n -1)

echo "HTTP Status Code: ${HTTP_CODE}"
echo "Response Body: ${RESPONSE_BODY}"

case ${HTTP_CODE} in
    201)
        echo "✅ Organization '${ORG_NAME}' created successfully!"
        echo "Organization details:"
        echo "${RESPONSE_BODY}"
        ;;
    409)
        echo "ℹ️  Organization '${ORG_NAME}' already exists"
        echo "Getting existing organization details..."
        curl -s -H "Authorization: token ${GITEA_TOKEN}" "${API_ENDPOINT}/${ORG_NAME}"
        ;;
    422)
        echo "❌ Error: Invalid organization data"
        echo "Response: ${RESPONSE_BODY}"
        exit 1
        ;;
    401)
        echo "❌ Error: Authentication failed"
        echo "Please check admin credentials"
        exit 1
        ;;
    *)
        echo "❌ Error: Failed to create organization (HTTP ${HTTP_CODE})"
        echo "Response: ${RESPONSE_BODY}"
        exit 1
        ;;
esac

echo "=== Organization creation completed ==="
