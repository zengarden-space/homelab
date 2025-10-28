# RBAC Operator

Kubernetes operator that automatically manages RoleBindings based on User CRDs.

## Overview

The RBAC Operator eliminates manual RoleBinding configuration by:
- Watching User CRDs for role assignments
- Reading namespace configuration from ClusterRole annotations
- Discovering application namespaces dynamically from ArgoCD Applications
- Creating per-user RoleBindings in appropriate namespaces
- Reconciling every 5 minutes to ensure consistency

## Quick Start

### 1. Deploy the Operator

```bash
cd ~/dev/homelab/system/helmfile
helmfile sync
```

This deploys ClusterRoles with namespace annotations and the operator.

### 2. Create a User

```bash
kubectl apply -f - <<EOF
apiVersion: zengarden.space/v1
kind: User
metadata:
  name: john-doe
spec:
  email: john.doe@example.com
  roles:
    - app-developer
  enabled: true
EOF
```

### 3. Verify

```bash
# Check user status
kubectl get users

# View created RoleBindings
kubectl get rolebindings -A -l zengarden.space/user=john-doe
```

## Role Mapping

| Role | Target Namespaces | ClusterRole |
|------|------------------|-------------|
| `app-developer` | `@argocd` (all ArgoCD app namespaces) | `homelab:app-developer` |
| `platform-operator` | `@argocd,argocd,gitea,metabase,victoria-metrics` | `homelab:platform-operator` |
| `system-admin` | `@argocd,argocd,gitea,...,cert-manager,secrets-system,...` | `homelab:system-admin` |

Namespaces are configured via ClusterRole `zengarden.space/namespaces` annotation. The `@argocd` token dynamically expands to all ArgoCD Application namespaces.

## Documentation

**Full documentation:** [RBAC Operator Documentation](../../../../docs/content/operations/rbac-operator.mdx)

See the documentation site for:
- Architecture and how it works
- Complete deployment guide
- Usage examples
- Troubleshooting
- Best practices
- Migration from static RoleBindings

## Directory Structure

```
rbac-operator/
├── Chart.yaml                       # Helm chart metadata
├── values.yaml                      # Configuration values
├── files/                           # Operator scripts
│   ├── rbac-service.py             # Main operator logic
│   ├── rbac-handler.sh             # Shell-operator hook
│   └── requirements.txt            # Python dependencies
├── templates/                       # Kubernetes manifests
│   ├── statefulset.yaml            # Operator deployment
│   ├── rbac.yaml                   # Operator permissions
│   ├── serviceaccount.yaml
│   ├── hooks-configmap.yaml
│   ├── rbac-service-configmap.yaml
│   └── NOTES.txt
└── examples/                        # Sample resources
    ├── sample-user.yaml            # Example User CRDs
    └── namespace-labels.yaml       # Namespace labeling examples
```

## Architecture

The operator uses the shell-operator pattern:
- **Shell-operator** container watches User, Application, and Namespace resources
- **Python service** sidecar performs reconciliation and creates RoleBindings
- **File-based IPC** for communication between containers
- **StatefulSet** deployment with PVC for pip packages

## Monitoring

```bash
# Check operator status
kubectl get pods -n rbac-system -l app.kubernetes.io/name=rbac-operator

# View logs
kubectl logs -n rbac-system -l app.kubernetes.io/name=rbac-operator -c rbac-service -f
```

## Common Commands

```bash
# List all users
kubectl get users

# Get user details
kubectl get user john-doe -o yaml

# Check created RoleBindings
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=rbac-operator

# Test user permissions
kubectl auth can-i get pods -n dev-retroboard --as=john.doe@example.com
```

## Configuration

Edit `values.yaml` to customize:
- Resource limits
- Reconciliation interval (default: 5 minutes)
- Log level
- Security context settings

## Security

- Runs as non-root (UID 64535)
- Read-only root filesystem
- Minimal RBAC permissions
- No secret access
- All changes auditable via User status

## Related

- [RBAC System README](../README.md) - Overall RBAC architecture
- [ClusterRoles](../cluster-roles/) - All ClusterRole definitions
- [User CRD](../rbac-crds/) - User resource schema
- [Deployment Guide](DEPLOYMENT.md) - Detailed deployment instructions
