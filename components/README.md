# Components Structure

This directory contains the modularized helmfiles, split by namespace from the original monolithic helmfile. Each component now manages its own configuration and secrets locally.

## Directory Structure

Each subdirectory represents a Kubernetes namespace and contains:
- `helmfile.yaml.gotmpl` - The helmfile for that specific namespace
- `env.yaml` - Environment-specific configuration and secrets (if needed)
- `env.yaml.template` - Template for environment configuration with empty values

## Components

### Core Infrastructure
- **metallb-system** - MetalLB load balancer and IP range configuration
  - Configuration: Load balancer IP ranges
- **cert-manager** - Certificate management, trust manager, internal CA, and Let's Encrypt
  - Secrets: Cloudflare account and token for Let's Encrypt
- **external-secrets-system** - External secrets operator
  - No local configuration needed

### Networking
- **external-dns** - DNS management with Mikrotik provider
  - Secrets: Mikrotik router credentials (URL, username, password)
- **ingress-nginx** - Internal ingress controller
  - No local configuration needed
- **external-tunnel** - External ingress controller and Cloudflare tunnel
  - No local configuration needed (uses Kubernetes secrets)

### Authentication & Security
- **authelia** - Authentication and authorization service
  - Configuration: Domain name for authentication

### Monitoring
- **victoria-metrics** - Metrics collection and Grafana dashboard
  - No local configuration needed
- **node-exporter** - Node metrics collection
  - No local configuration needed

### GitOps & CI/CD
- **argocd** - ArgoCD for GitOps workflows
  - Secrets: GitHub webhook secret
- **gitea** - Git repository hosting
  - Secrets: Admin password, Docker Hub credentials
- **gitea-runner** - CI/CD runner for Gitea
  - No local configuration needed

## Security Benefits

- **Isolation**: Each component only has access to its required secrets
- **Least Privilege**: Components can't access secrets from other components
- **Maintainability**: Secrets are located where they're used
- **Version Control Safety**: Each component can have its own `.env` file gitignored

## Usage

### Deploy All Components
From the root directory:
```bash
helmfile -f components.yaml apply
```

### Deploy Specific Component
```bash
cd components/<namespace>
helmfile apply
```

### Deploy Multiple Components
```bash
helmfile -f components.yaml -l name=metallb apply
helmfile -f components.yaml -l name=cert-manager apply
```

### Setting up Environment Files
1. Copy `env.yaml.template` to `env.yaml` in each component directory
2. Fill in the required values in each `env.yaml` file
3. Add `env.yaml` to `.gitignore` to avoid committing secrets

## Secret Management

### Previously Centralized (helmfile/env.yaml)
All secrets were in a single file, creating security and maintenance challenges.

### Now Distributed by Component:
- **metallb-system/env.yaml**: `loadBalancing.ipRange`
- **cert-manager/env.yaml**: `letsEncrypt.cloudflareAccount`, `letsEncrypt.cloudflareToken`
- **external-dns/env.yaml**: `externalDns.mikrotikBaseUrl`, `externalDns.mikrotikUsername`, `externalDns.mikrotikPassword`
- **authelia/env.yaml**: `authelia.domain`
- **argocd/env.yaml**: `argocd.webhookSecret`
- **gitea/env.yaml**: `gitea.password`, `dockerHub.username`, `dockerHub.password`

### Unused Secrets (from original helmfile)
These were moved out but not assigned to components as they're not currently used:
- `minio.password` (from commented velero section)
- `veleroBackup.awsAccessKey` (from commented velero section)
- `veleroBackup.awsSecretKey` (from commented velero section)

## Dependencies

Some components have dependencies on others. The recommended deployment order is:

1. Core Infrastructure (metallb-system, cert-manager, external-secrets-system)
2. Networking (external-dns, ingress-nginx, external-tunnel)
3. Authentication (authelia)
4. Monitoring (victoria-metrics, node-exporter)
5. GitOps & CI/CD (argocd, gitea, gitea-runner)

Dependencies are handled automatically when using `helmfile -f components.yaml apply`.
