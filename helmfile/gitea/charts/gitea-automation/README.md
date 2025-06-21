# Gitea Automation

This Helm chart provides automation for Gitea, including organization creation and two-way repository synchronization between GitHub and Gitea.

## Features

- Creates organizations via Gitea REST API
- Two-way repository synchronization between GitHub and Gitea
- Personal access token generation and management for automation
- Smart token validation - checks existing tokens before regeneration
- Configurable organization settings (name, description, website, visibility)
- Uses ConfigMap to store automation scripts
- Secure job execution with proper security contexts
- Automatic retry logic with backoff
- Checks if organization already exists before creating
- Enumerates and syncs repositories between GitHub and Gitea organizations

## Token Management

The chart includes intelligent token management:
- Before generating new tokens, it checks if secrets already exist
- Validates that existing tokens have the correct scopes and user
- Only regenerates tokens when necessary (different scopes/user or missing token)
- Automatically cleans up outdated tokens when configuration changes

## Configuration

### Organization Settings

```yaml
organization:
  name: "zengarden-space"          # Organization name
  description: "ZenGarden Space Organization"  # Organization description
  website: "https://zengarden.space"          # Organization website
  visibility: "public"                        # public or private
```

### Gitea Configuration

```yaml
gitea:
  service:
    name: "gitea-http"      # Gitea service name
    namespace: "gitea"      # Gitea namespace
    port: 3000             # Gitea service port
  admin:
    username: "gitea_admin" # Admin username
    # Password is read from gitea-admin-secret
```

### GitHub Configuration

```yaml
github:
  token: "github_pat_..."    # GitHub personal access token
  organization: "zengarden-space"  # GitHub organization name
```

### Personal Access Tokens

```yaml
personalAccessTokens:
  enabled: true
  tokens:
    org-creator:
      user: gitea_admin
      scopes: "write:organization,write:repository"
```

## Prerequisites

- Gitea must be running and accessible
- Admin credentials must be available in a secret named `gitea-admin-secret` with key `password`
- GitHub personal access token with appropriate permissions for organization and repository access
- The job requires network access to both Gitea service and GitHub API

## Container Images

The chart uses a multi-container approach for optimal security and functionality:
- **Main container**: `alpine/curl:8.10.1` - Lightweight Alpine Linux with curl for API calls
- **Init container**: `ghcr.io/jqlang/jq:1.8.0` - Copies the jq binary for JSON processing
- This approach avoids installing packages at runtime and keeps the main container minimal

## Usage

The chart is designed to be used as a Helm hook that runs after Gitea installation/upgrade:

```bash
helm install gitea-org-creator ./gitea-org-creator -n gitea
```

## Script Functionality

The shell script (`files/create-org.sh`) performs the following:

1. Waits for Gitea to be accessible
2. Checks if the organization already exists
3. Creates the organization if it doesn't exist
4. Provides detailed logging and error handling
5. Handles various HTTP response codes appropriately

## Security

- Runs with non-root user (UID 1000)
- Drops all capabilities
- Uses read-only root filesystem where possible
- Follows Kubernetes security best practices
