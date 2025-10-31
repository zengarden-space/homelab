# Homelab GitHub Actions

Reusable GitHub Actions for managing Kubernetes manifests in the homelab environment.

## Available Actions

### 1. generate-manifests

Generates Kubernetes manifests from Helm charts using `helm template`.

### 2. add-composite-ingress-host

Creates a CompositeIngressHost YAML file for the PartialIngress operator. This defines the base environment and hostname pattern for partial deployments.

**Usage:**

```yaml
- name: Generate CompositeIngressHost
  uses: zengarden-space/homelab/actions/add-composite-ingress-host@main
  with:
    base-host: "myapp.dev.homelab.int.zengarden.space"  # Required: base hostname
    host-pattern: "myapp-*.homelab.int.zengarden.space"  # Required: pattern for PRs
    ingress-class: internal  # Optional: defaults to 'internal'
    output-file: compositeingresshost.yaml  # Optional: output file path
```

**Outputs:**
- `manifest-file`: Path to the generated CompositeIngressHost manifest

### 3. add-partial-ingress

Converts rendered Ingress resources to PartialIngress for PR/branch environments. Generates a unique environment ID from the slug (branch name) using SHA256 hash.

**Usage:**

```yaml
- name: Convert to PartialIngress
  uses: zengarden-space/homelab/actions/add-partial-ingress@main
  with:
    slug: ${{ github.head_ref }}  # Required: branch name or slug
    manifest-file: manifest-dev.yaml  # Required: manifest to modify
    base-domain: dev.homelab.int.zengarden.space  # Optional: domain to replace
```

**Outputs:**
- `manifest-file`: Path to modified manifest with PartialIngress
- `environment-id`: Environment identifier (sha256 hash of slug, 8 chars)

**Transformations:**
- `Ingress` → `PartialIngress` (apiVersion: networking.zengarden.space/v1)
- Generates unique ID: `sha256(branch_name)[:8]`
- `myapp.dev.domain` → `myapp-abc12345.domain` (where `abc12345` is hash of branch name)
- Removes TLS sections
- Removes cert-manager and external-dns annotations

### 4. push-manifests-with-cih

Pushes manifests with optional CompositeIngressHost to the manifests repository. Supports both dev and CI environments.

**Usage:**

```yaml
- name: Push to dev with CIH
  uses: zengarden-space/homelab/actions/push-manifests-with-cih@main
  with:
    environment: dev  # Required: dev, ci-pr-123, prod
    manifest-file: manifest.yaml  # Required: main manifest
    cih-file: compositeingresshost.yaml  # Optional: CIH manifest
    token: ${{ secrets.CONTENT_WRITE_TOKEN }}  # Required
```

**Features:**
- Automatic retry with exponential backoff
- Supports CI environments: `ci-pr-<number>`
- Optional CompositeIngressHost deployment

### 5. push-manifests

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

### 6. review-manifests

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

## Complete Workflow Examples

### Standard Workflow (dev + prod)

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: 'gitea.homelab.int.zengarden.space'
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
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
          image-tag: ${{ steps.extract-tag.outputs.tag }}

      - name: Generate prod manifests
        if: github.ref == 'refs/heads/main'
        id: gen-prod
        uses: zengarden-space/homelab/actions/generate-manifests@main
        with:
          environment: prod
          image-tag: ${{ steps.extract-tag.outputs.tag }}

      - name: Deploy to dev (auto)
        if: github.ref == 'refs/heads/main'
        uses: zengarden-space/homelab/actions/push-manifests@main
        with:
          environment: dev
          manifest-file: ${{ steps.gen-dev.outputs.manifest-file }}
          token: ${{ secrets.CONTENT_WRITE_TOKEN }}

      - name: Create prod review PR
        if: github.ref == 'refs/heads/main'
        uses: zengarden-space/homelab/actions/review-manifests@main
        with:
          environment: prod
          manifest-file: ${{ steps.gen-prod.outputs.manifest-file }}
          token: ${{ secrets.CONTENT_WRITE_TOKEN }}
```

### PartialIngress Workflow (dev + PR + prod)

```yaml
name: CI/CD Pipeline with PartialIngress

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  REGISTRY: 'gitea.homelab.int.zengarden.space'
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # ... Docker build, Helm lint, Trivy scan, etc ...

      - name: Generate dev manifests
        id: gen-dev
        uses: zengarden-space/homelab/actions/generate-manifests@main
        with:
          environment: dev
          image-tag: ${{ steps.extract-tag.outputs.tag }}

      - name: Generate prod manifests
        if: github.ref == 'refs/heads/main'
        id: gen-prod
        uses: zengarden-space/homelab/actions/generate-manifests@main
        with:
          environment: prod
          image-tag: ${{ steps.extract-tag.outputs.tag }}

      # Dev deployment with CompositeIngressHost
      - name: Generate CompositeIngressHost for dev
        if: github.ref == 'refs/heads/main'
        id: gen-cih
        uses: zengarden-space/homelab/actions/add-composite-ingress-host@main
        with:
          base-host: "myapp.dev.homelab.int.zengarden.space"
          host-pattern: "myapp-*.homelab.int.zengarden.space"
          ingress-class: "internal"

      - name: Deploy to dev
        if: github.ref == 'refs/heads/main'
        uses: zengarden-space/homelab/actions/push-manifests-with-cih@main
        with:
          environment: dev
          manifest-file: ${{ steps.gen-dev.outputs.manifest-file }}
          cih-file: ${{ steps.gen-cih.outputs.manifest-file }}
          token: ${{ secrets.CONTENT_WRITE_TOKEN }}

      # PR deployment with PartialIngress
      - name: Generate CI manifests for PR
        if: github.event_name == 'pull_request'
        id: gen-ci
        run: |
          cp ${{ steps.gen-dev.outputs.manifest-file }} manifest-ci.yaml
          echo "manifest-file=manifest-ci.yaml" >> $GITHUB_OUTPUT

      - name: Convert to PartialIngress for PR
        if: github.event_name == 'pull_request'
        id: partial-ingress
        uses: zengarden-space/homelab/actions/add-partial-ingress@main
        with:
          slug: ${{ github.head_ref }}
          manifest-file: ${{ steps.gen-ci.outputs.manifest-file }}

      - name: Deploy to CI environment
        if: github.event_name == 'pull_request'
        uses: zengarden-space/homelab/actions/push-manifests-with-cih@main
        with:
          environment: ci-${{ steps.partial-ingress.outputs.environment-id }}
          manifest-file: ${{ steps.partial-ingress.outputs.manifest-file }}
          token: ${{ secrets.CONTENT_WRITE_TOKEN }}

      # Prod deployment via PR
      - name: Create prod review PR
        if: github.ref == 'refs/heads/main'
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
└── {cluster}/                    # Default: homelab
    ├── dev/
    │   └── {project-name}/
    │       ├── manifest.yaml              # Application resources
    │       └── compositeingresshost.yaml  # Optional: for PartialIngress
    ├── ci-{env-id}/             # PR/branch environments (env-id = sha256(branch_name)[:8])
    │   └── {project-name}/
    │       └── manifest.yaml              # PartialIngress resources
    └── prod/
        └── {project-name}/
            └── manifest.yaml              # Production resources
```

**Examples:**
- Dev: `homelab/dev/retroboard/manifest.yaml`
- Dev CIH: `homelab/dev/retroboard/compositeingresshost.yaml`
- PR/Branch: `homelab/ci-abc12345/retroboard/manifest.yaml` (where `abc12345` = sha256(branch_name)[:8])
- Prod: `homelab/prod/retroboard/manifest.yaml`

## Required Secrets

- `CONTENT_WRITE_TOKEN`: Gitea personal access token with:
  - `repo` scope (read/write access to manifests repository)
  - Organization: `zengarden-space`

## Prerequisites

- Helm chart in `./helm/{project-name}/`
- Values files: `./helm/values-dev.yaml` and/or `./helm/values-prod.yaml`
- Manifests repository: `zengarden-space/manifests`