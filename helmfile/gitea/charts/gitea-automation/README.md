# Gitea Organization Creator

This Helm chart creates organizations in Gitea using the Gitea API.

## Features

- Creates organizations via Gitea REST API
- Configurable organization settings (name, description, website, visibility)
- Uses ConfigMap to store the shell script
- Secure job execution with proper security contexts
- Automatic retry logic with backoff
- Checks if organization already exists before creating

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

## Prerequisites

- Gitea must be running and accessible
- Admin credentials must be available in a secret named `gitea-admin-secret` with key `password`
- The job requires network access to the Gitea service

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
