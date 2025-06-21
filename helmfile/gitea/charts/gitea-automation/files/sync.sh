#!/bin/sh
set -eu

echo "=== Gitea-GitHub Two-Way Sync Script ==="
echo "Organization: ${ORG_NAME}"
echo "GitHub Org: ${GITHUB_ORG}"

# Download jq if not available
if ! command -v jq > /dev/null 2>&1; then
    echo "Downloading jq..."
    JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.8.0/jq-linux-arm64"
    curl -L -o /tmp/jq "${JQ_URL}"
    chmod +x /tmp/jq
    export PATH="/tmp:${PATH}"
    echo "✅ jq downloaded and available"
else
    echo "✅ jq is already available"
fi

# Verify jq is working
if ! jq --version > /dev/null 2>&1; then
    echo "❌ Error: jq is not working properly"
    exit 1
fi


# API endpoints
GITEA_URL="http://${GITEA_SERVICE_NAME}.${GITEA_NAMESPACE}.svc.cluster.local:${GITEA_SERVICE_PORT}"
GITEA_API="${GITEA_URL}/api/v1"
GITHUB_API="https://api.github.com"

echo "Gitea URL: ${GITEA_URL}"
echo "GitHub API: ${GITHUB_API}"

# Wait for Gitea to be ready
echo "Checking Gitea connectivity..."
for i in {1..30}; do
    if curl -sf "${GITEA_URL}/api/healthz" > /dev/null 2>&1; then
        echo "✅ Gitea is accessible"
        break
    fi
    echo "⏳ Waiting for Gitea to be ready... (attempt $i/30)"
    sleep 10
done

if ! curl -sf "${GITEA_URL}/api/healthz" > /dev/null 2>&1; then
    echo "❌ Error: Gitea is not accessible after 5 minutes"
    exit 1
fi

# Ensure organization exists in Gitea
echo "Ensuring Gitea organization '${ORG_NAME}' exists..."
if ! curl -sf -H "Authorization: token ${GITEA_TOKEN}" "${GITEA_API}/orgs/${ORG_NAME}" > /dev/null 2>&1; then
    echo "Creating Gitea organization '${ORG_NAME}'..."
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
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -d "${ORG_PAYLOAD}" \
        "${GITEA_API}/orgs")
    
    HTTP_CODE=$(echo "${RESPONSE}" | tail -n1)
    case ${HTTP_CODE} in
        201|409)
            echo "✅ Gitea organization ready"
            ;;
        *)
            echo "❌ Failed to create Gitea organization (HTTP ${HTTP_CODE})"
            echo "${RESPONSE}" | head -n -1
            exit 1
            ;;
    esac
else
    echo "✅ Gitea organization '${ORG_NAME}' already exists"
fi

# Function to get repositories from GitHub
get_github_repos() {
    curl -sf -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${GITHUB_API}/orgs/${GITHUB_ORG}/repos?type=all&per_page=100" | \
        jq -r '.[].name' 2>/dev/null || echo ""
}

# Function to get repositories from Gitea
get_gitea_repos() {
    curl -sf -H "Authorization: token ${GITEA_TOKEN}" \
        "${GITEA_API}/orgs/${ORG_NAME}/repos?limit=100" | \
        jq -r '.[].name' 2>/dev/null || echo ""
}

# Function to create repository in GitHub
create_github_repo() {
    local repo_name="$1"
    local description="$2"
    echo "Creating GitHub repository: ${repo_name}"
    
    REPO_PAYLOAD=$(cat <<EOF
{
    "name": "${repo_name}",
    "description": "${description}",
    "private": false,
    "has_issues": true,
    "has_projects": true,
    "has_wiki": true
}
EOF
)
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        -d "${REPO_PAYLOAD}" \
        "${GITHUB_API}/orgs/${GITHUB_ORG}/repos")
    
    HTTP_CODE=$(echo "${RESPONSE}" | tail -n1)
    if [ "${HTTP_CODE}" = "201" ]; then
        return 0
    else
        echo "GitHub API Error (HTTP ${HTTP_CODE}): $(echo "${RESPONSE}" | head -n -1)"
        return 1
    fi
}

# Function to create repository in Gitea via migration from GitHub
create_gitea_repo() {
    local repo_name="$1"
    local description="$2"
    echo "Migrating GitHub repository '${repo_name}' to Gitea..."
    
    REPO_PAYLOAD=$(cat <<EOF
{
    "clone_addr": "https://github.com/${GITHUB_ORG}/${repo_name}.git",
    "auth_username": "",
    "auth_password": "${GITHUB_TOKEN}",
    "uid": 0,
    "repo_owner": "${ORG_NAME}",
    "repo_name": "${repo_name}",
    "mirror": false,
    "private": false,
    "description": "${description}",
    "issues": false,
    "labels": false,
    "milestones": false,
    "pull_requests": false,
    "releases": false,
    "wiki": false
}
EOF
)
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Authorization: token ${GITEA_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "${REPO_PAYLOAD}" \
        "${GITEA_API}/repos/migrate")
    
    HTTP_CODE=$(echo "${RESPONSE}" | tail -n1)
    if [ "${HTTP_CODE}" = "201" ]; then
        echo "✅ Successfully migrated repository to organization"
    else
        echo "Gitea Migration Error (HTTP ${HTTP_CODE}): $(echo "${RESPONSE}" | head -n -1)"
        return 1
    fi
}

# Function to get repository description from GitHub
get_github_repo_description() {
    local repo_name="$1"
    curl -sf -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${GITHUB_API}/repos/${GITHUB_ORG}/${repo_name}" | \
        jq -r '.description // ""' 2>/dev/null || echo ""
}

# Function to get repository description from Gitea
get_gitea_repo_description() {
    local repo_name="$1"
    curl -sf -H "Authorization: token ${GITEA_TOKEN}" \
        "${GITEA_API}/repos/${ORG_NAME}/${repo_name}" | \
        jq -r '.description // ""' 2>/dev/null || echo ""
}

# Test GitHub API access
echo "Testing GitHub API access..."
if ! curl -sf -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "${GITHUB_API}/user" > /dev/null 2>&1; then
    echo "❌ Error: Cannot access GitHub API. Check your token."
    exit 1
fi
echo "✅ GitHub API access confirmed"

# Get repositories from both platforms
echo "Enumerating repositories..."
echo "Getting GitHub repositories..."
GITHUB_REPOS=$(get_github_repos)
echo "Getting Gitea repositories..."
GITEA_REPOS=$(get_gitea_repos)

echo "GitHub repositories:"
if [ -n "${GITHUB_REPOS}" ]; then
    echo "${GITHUB_REPOS}" | sed 's/^/  - /'
else
    echo "  (none)"
fi
echo ""
echo "Gitea repositories:"
if [ -n "${GITEA_REPOS}" ]; then
    echo "${GITEA_REPOS}" | sed 's/^/  - /'
else
    echo "  (none)"
fi
echo ""

# Sync repositories from GitHub to Gitea
echo "=== Migrating repositories from GitHub to Gitea ==="
for repo in ${GITHUB_REPOS}; do
    if [ -z "$repo" ]; then
        continue
    fi
    
    if echo "${GITEA_REPOS}" | grep -q "^${repo}$"; then
        echo "✅ Repository '${repo}' already exists in Gitea"
    else
        echo "➡️  Migrating '${repo}' from GitHub to Gitea..."
        description=$(get_github_repo_description "${repo}")
        if create_gitea_repo "${repo}" "${description}"; then
            echo "✅ Successfully migrated '${repo}' to Gitea"
        else
            echo "❌ Failed to migrate '${repo}' to Gitea"
        fi
    fi
done

# Sync repositories from Gitea to GitHub
echo ""
echo "=== Syncing from Gitea to GitHub ==="
for repo in ${GITEA_REPOS}; do
    if [ -z "$repo" ]; then
        continue
    fi
    
    if echo "${GITHUB_REPOS}" | grep -q "^${repo}$"; then
        echo "✅ Repository '${repo}' already exists in GitHub"
    else
        echo "➡️  Creating '${repo}' in GitHub..."
        description=$(get_gitea_repo_description "${repo}")
        if create_github_repo "${repo}" "${description}"; then
            echo "✅ Successfully created '${repo}' in GitHub"
        else
            echo "❌ Failed to create '${repo}' in GitHub"
        fi
    fi
done

echo ""
echo "=== Sync completed ==="
