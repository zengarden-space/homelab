# Homelab GitHub Actions

Reusable GitHub Actions for managing Kubernetes manifests in the homelab environment.

## Available Actions

### 1. generate-manifests

Generates Kubernetes manifests from Helm charts using `helm template`.

**Usage:**

```yaml
- name: Generate manifests
  uses: zengarden-space/homelab/actions/generate-manifests@main
  with:
    environment: dev  # Required: dev or prod
    project-name: my-app  # Optional: defaults to repository name
    image-tag: sha-abc123  # Required: Docker image tag
    cluster: homelab  # Optional: defaults to 'homelab'
```

**Outputs:**
- `manifest-file`: Path to the generated manifest file
- `project-name`: Resolved project name

### 2. push-manifests

Pushes manifests directly to the main branch of the manifests repository. Used for dev environments with auto-deploy.

**Usage:**

```yaml
- name: Push to dev
  uses: zengarden-space/homelab/actions/push-manifests@main
  with:
    environment: dev  # Required: dev or prod
    manifest-file: manifest-dev.yaml  # Required: path to manifest
    token: ${{ secrets.CONTENT_WRITE_TOKEN }}  # Required: Gitea token
    project-name: my-app  # Optional: defaults to repository name
    cluster: homelab  # Optional: defaults to 'homelab'
    manifests-repo: zengarden-space/manifests  # Optional
    commit-message: "Custom message"  # Optional
```

**Features:**
- Automatic retry with exponential backoff (5 attempts)
- Handles concurrent push conflicts
- Skip commit if no changes detected

### 3. review-manifests

Creates a pull request in the manifests repository for review. Used for prod deployments requiring approval.

**Usage:**

```yaml
- name: Create prod PR
  uses: zengarden-space/homelab/actions/review-manifests@main
  with:
    environment: prod  # Required: dev or prod
    manifest-file: manifest-prod.yaml  # Required: path to manifest
    token: ${{ secrets.CONTENT_WRITE_TOKEN }}  # Required: Gitea token
    project-name: my-app  # Optional: defaults to repository name
    cluster: homelab  # Optional: defaults to 'homelab'
    branch-name: prod-my-app  # Optional: defaults to {env}-{project}
    manifests-repo: zengarden-space/manifests  # Optional
    gitea-url: https://gitea.homelab.int.zengarden.space  # Optional
```

**Outputs:**
- `pr-exists`: Whether a PR already exists (0 or 1)
- `pr-created`: Whether a new PR was created (true/false)

**Features:**
- Checks for existing PRs to avoid duplicates
- Force-pushes to update existing branch
- Auto-generates PR title and description

## Complete Workflow Example

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [ main, develop ]

env:
  REGISTRY: 'gitea.homelab.int.zengarden.space'
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # ... Docker build steps ...

      - name: Generate dev manifests
        id: gen-dev
        uses: zengarden-space/homelab/actions/generate-manifests@main
        with:
          environment: dev
          image-tag: ${{ steps.meta.outputs.tag }}

      - name: Generate prod manifests
        id: gen-prod
        uses: zengarden-space/homelab/actions/generate-manifests@main
        with:
          environment: prod
          image-tag: ${{ steps.meta.outputs.tag }}

      - name: Deploy to dev (auto)
        uses: zengarden-space/homelab/actions/push-manifests@main
        with:
          environment: dev
          manifest-file: ${{ steps.gen-dev.outputs.manifest-file }}
          token: ${{ secrets.CONTENT_WRITE_TOKEN }}

      - name: Create prod review PR
        uses: zengarden-space/homelab/actions/review-manifests@main
        with:
          environment: prod
          manifest-file: ${{ steps.gen-prod.outputs.manifest-file }}
          token: ${{ secrets.CONTENT_WRITE_TOKEN }}
```

## Directory Structure

Generated manifests are organized in the manifests repository as:

```
manifests/
└── {cluster}/
    ├── dev/
    │   └── {project-name}/
    │       └── manifest.yaml
    └── prod/
        └── {project-name}/
            └── manifest.yaml
```

Default: `homelab/dev/{project}/manifest.yaml`

## Required Secrets

- `CONTENT_WRITE_TOKEN`: Gitea personal access token with:
  - `repo` scope (read/write access to manifests repository)
  - Organization: `zengarden-space`

## Prerequisites

- Helm chart in `./helm/{project-name}/`
- Values files: `./helm/values-dev.yaml` and/or `./helm/values-prod.yaml`
- Manifests repository: `zengarden-space/manifests`