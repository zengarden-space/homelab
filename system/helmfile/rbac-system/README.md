# RBAC System

Comprehensive RBAC management for the homelab, including static ClusterRoles and dynamic RoleBinding automation.

## Overview

The `rbac-system` consists of three components:

1. **ClusterRoles** (`cluster-roles/`): All ClusterRoles and static ClusterRoleBindings
2. **User CRDs** (`rbac-crds/`): Custom resource definitions for User resources
3. **RBAC Operator** (`rbac-operator/`): Kubernetes operator that automatically creates RoleBindings based on User CRDs

## Directory Structure

```
rbac-system/
├── helmfile.yaml                    # Main helmfile orchestrating all components
├── README.md                        # This file
├── cluster-roles/                   # ClusterRoles for all users
│   ├── helmfile.yaml
│   └── manifests/
│       ├── Chart.yaml
│       └── templates/
│           ├── rbac-app-developer.yaml      # App developer ClusterRole
│           ├── rbac-platform-operator.yaml  # Platform operator ClusterRole
│           ├── rbac-system-admin.yaml       # System admin ClusterRole
│           └── rbac-cluster-admin.yaml      # Cluster admin ClusterRole + ClusterRoleBinding
├── rbac-crds/                       # User CRD chart
│   ├── Chart.yaml
│   └── templates/
│       └── user-crd.yaml           # User CRD definition
└── rbac-operator/                   # Dynamic RBAC operator
    ├── Chart.yaml
    ├── values.yaml
    ├── README.md                    # Operator documentation
    ├── DEPLOYMENT.md                # Deployment guide
    ├── files/                       # Operator scripts
    │   ├── rbac-service.py         # Main operator logic
    │   ├── rbac-handler.sh         # Shell-operator hook
    │   └── requirements.txt        # Python dependencies
    ├── templates/                   # Kubernetes manifests
    │   ├── _helpers.tpl
    │   ├── serviceaccount.yaml
    │   ├── rbac.yaml               # Operator permissions
    │   ├── hooks-configmap.yaml
    │   ├── rbac-service-configmap.yaml
    │   ├── statefulset.yaml        # Operator deployment
    │   └── NOTES.txt
    └── examples/                    # Sample resources
        ├── sample-user.yaml        # Example User CRDs
        └── namespace-labels.yaml   # Namespace label examples
```

## Components

### ClusterRoles

Defines all ClusterRoles for the homelab:

**User Roles:**
- **`homelab:app-developer`**: Read-only access to application resources (pods, logs, etc.)
- **`homelab:platform-operator`**: CRUD access to workloads, manage ArgoCD Applications
- **`homelab:system-admin`**: Full access to all namespaced resources and system operators

**Admin Roles:**
- **`homelab:cluster-admin`**: Break-glass unrestricted access with static ClusterRoleBinding (only for `oleksiy.pylypenko@gmail.com`)

**Binding Strategy:**
- **User roles**: Bound via dynamic RoleBindings created by RBAC operator (per namespace)
- **Cluster admin**: Bound via static ClusterRoleBinding (cluster-wide)
- **Legacy**: Some static RoleBindings exist (being replaced by operator)

### RBAC Operator

Automatically manages RoleBindings based on:
- **User CRDs** (`zengarden.space/v1`): Define users and their roles
- **ClusterRole annotations**: Define which namespaces each role applies to
- **ArgoCD Applications**: Dynamically discover application namespaces via `@argocd` token

#### How It Works

1. **User Creation**: Admin creates User CRD specifying email and roles
2. **ClusterRole Configuration**: Each ClusterRole has annotations:
   - `zengarden.space/role`: The role name (e.g., `app-developer`)
   - `zengarden.space/namespaces`: Comma-separated list of namespaces, supports `@argocd` token
3. **Namespace Discovery**:
   - Static namespaces from ClusterRole `zengarden.space/namespaces` annotation
   - Dynamic namespaces via `@argocd` token (expands to all ArgoCD Application namespaces)
4. **RoleBinding Creation**: For each user with a role:
   - Operator reads ClusterRole annotations to get namespace list
   - Creates RoleBinding named `homelab:<role>:<username>` in each namespace
   - RoleBinding references the ClusterRole (e.g., `homelab:app-developer`)
5. **Reconciliation**: Runs every 5 minutes + on-demand when Users, ClusterRoles, or Applications change

#### Supported Roles

| Role | Namespaces Annotation | ClusterRole | Access Level |
|------|-----------|-------------|--------------|
| `app-developer` | `@argocd` | `homelab:app-developer` | Read-only (view logs, exec) |
| `platform-operator` | `@argocd,argocd,gitea,metabase,victoria-metrics` | `homelab:platform-operator` | CRUD workloads, manage ArgoCD apps |
| `system-admin` | `@argocd,argocd,gitea,...,cert-manager,...` | `homelab:system-admin` | Full access to resources |

**Note**: `@argocd` token expands to all namespaces where ArgoCD Applications are deployed. ClusterRoles are defined in `system/helmfile/rbac-system/cluster-roles`.

## Deployment

### Prerequisites

1. ArgoCD must be installed (for dynamic namespace discovery)
2. ClusterRoles must exist with proper annotations

### Deploy All RBAC Components

```bash
cd /Users/oleksiyp/dev/homelab/system/helmfile
helmfile sync
```

This deploys in order:
1. ClusterRoles with namespace annotations
2. User CRD
3. RBAC Operator

**No manual namespace labeling required!** Namespaces are configured via ClusterRole annotations.

### Create Users

```bash
kubectl apply -f rbac-system/rbac-operator/examples/sample-user.yaml
```

Or create individual users:

```yaml
apiVersion: zengarden.space/v1
kind: User
metadata:
  name: john-doe
spec:
  email: john.doe@example.com
  roles:
    - app-developer
  enabled: true
```

## Usage

### Managing Users

```bash
# List all users
kubectl get users

# Get user details
kubectl get user john-doe -o yaml

# Create user
kubectl apply -f user.yaml

# Update user roles
kubectl edit user john-doe

# Disable user
kubectl patch user john-doe --type=merge -p '{"spec":{"enabled":false}}'

# Delete user
kubectl delete user john-doe
```

### Viewing RoleBindings

```bash
# List all operator-managed RoleBindings
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=rbac-operator

# Check RoleBindings in specific namespace
kubectl get rolebindings -n dev-retroboard

# Describe RoleBinding
kubectl describe rolebinding homelab:app-developer:john-doe -n dev-retroboard
```

### Monitoring

```bash
# Check operator status
kubectl get pods -n rbac-system

# View operator logs
kubectl logs -n rbac-system -l app.kubernetes.io/name=rbac-operator -c rbac-service -f

# Check user reconciliation status
kubectl get user john-doe -o jsonpath='{.status.conditions[*].message}'
```

## RBAC Architecture

All RBAC components are unified in `system/helmfile/rbac-system`:

- **ClusterRoles** (`cluster-roles/`):
  - Defines all 4 ClusterRoles (app-developer, platform-operator, system-admin, cluster-admin)
  - Contains static ClusterRoleBinding for cluster-admin only
  - Contains legacy static RoleBindings (being replaced by operator)

- **RBAC Operator** (`rbac-operator/`):
  - Automates RoleBinding creation based on User CRDs
  - Discovers namespaces from ArgoCD and labels
  - Creates per-user RoleBindings in appropriate namespaces
  - Manages app-developer, platform-operator, and system-admin bindings

**Migration Path**: All static RoleBindings in `cluster-roles/` (except cluster-admin) will be replaced by User CRDs.

## Security

- Operator runs as non-root (UID 64535)
- Read-only root filesystem
- Minimal RBAC permissions (only what's needed)
- No direct secret access
- All changes auditable via User resource status

## Troubleshooting

See [DEPLOYMENT.md](rbac-operator/DEPLOYMENT.md#troubleshooting) for detailed troubleshooting steps.

Common issues:
- **RoleBindings not created**: Check ClusterRoles exist, namespace labels correct, ArgoCD apps exist
- **Operator not starting**: Check logs, verify ServiceAccount permissions
- **Permission denied**: Verify OIDC email matches User.spec.email

## Related Documentation

- [RBAC Operations Guide](/docs/content/operations/rbac.mdx)
- [RBAC Operator README](rbac-operator/README.md)
- [RBAC Operator Deployment Guide](rbac-operator/DEPLOYMENT.md)
- [ClusterRoles](cluster-roles/)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        User CRD                             │
│  (zengarden.space/v1, cluster-scoped)                       │
│  - email: user@example.com                                  │
│  - roles: [app-developer, platform-operator, system-admin]  │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                   RBAC Operator                             │
│  (StatefulSet in rbac-system namespace)                     │
│  ┌────────────────┐  ┌─────────────────────────────┐       │
│  │ Shell-Operator │  │ Python Service              │       │
│  │ - Watches CRDs │◄─┤ - Discovers namespaces      │       │
│  │ - File-based   │  │ - Creates RoleBindings      │       │
│  │   IPC          │  │ - Updates User status       │       │
│  └────────────────┘  └─────────────────────────────┘       │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│               Namespace Discovery                           │
│  ┌──────────────────┐  ┌────────────────┐  ┌─────────────┐ │
│  │ ArgoCD Apps      │  │ Platform NS    │  │ System NS   │ │
│  │ (app namespaces) │  │ (labeled)      │  │ (labeled)   │ │
│  └──────────────────┘  └────────────────┘  └─────────────┘ │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              RoleBinding Creation                           │
│  - app-developer → app namespaces                           │
│  - platform-operator → app + platform namespaces            │
│  - system-admin → app + platform + system namespaces        │
└─────────────────────────────────────────────────────────────┘
```

## Future Enhancements

1. **Cleanup on User deletion**: Automatically remove RoleBindings when User is deleted
2. **Cleanup on User disable**: Remove RoleBindings when `enabled: false`
3. **ClusterRoleBinding support**: For cluster-admin role via User CRD
4. **Group support**: Bind roles to Google OAuth groups
5. **Audit logging**: Track all RBAC changes
6. **Metrics**: Prometheus metrics for reconciliation status
7. **Webhook validation**: Validate User resources before admission
