# RBAC Operator Deployment Guide

Quick deployment guide for the RBAC Operator. For comprehensive documentation, see [RBAC Operator Documentation](../../../../docs/content/operations/rbac-operator.mdx).

## Prerequisites

1. **ClusterRoles must exist:**
   - `homelab:app-developer` (from `system/helmfile/rbac-system/cluster-roles`)
   - `homelab:platform-operator` (from `system/helmfile/rbac-system/cluster-roles`)
   - `homelab:system-admin` (from `system/helmfile/rbac-system/cluster-roles`)

2. **ArgoCD installed** for application namespace discovery

3. **Namespaces labeled** for platform/system classification

## Quick Deployment

### 1. Deploy All Components

```bash
cd ~/dev/homelab/system/helmfile
helmfile sync
```

This automatically deploys:
- User CRD
- Static RBAC (ClusterRoles)
- RBAC Operator

### 2. Label Namespaces

```bash
# Platform namespaces (platform-operator access)
kubectl label namespace argocd zengarden.space/role=platform
kubectl label namespace gitea zengarden.space/role=platform
kubectl label namespace metabase zengarden.space/role=platform
kubectl label namespace victoria-metrics zengarden.space/role=platform

# System namespaces (system-admin access)
kubectl label namespace cert-manager zengarden.space/role=system
kubectl label namespace secrets-system zengarden.space/role=system
kubectl label namespace metallb-system zengarden.space/role=system
kubectl label namespace ingress-nginx zengarden.space/role=system
kubectl label namespace external-dns zengarden.space/role=system
kubectl label namespace external-tunnel zengarden.space/role=system
kubectl label namespace cnpg-system zengarden.space/role=system
kubectl label namespace cilium-secrets zengarden.space/role=system
kubectl label namespace integrations zengarden.space/role=system
kubectl label namespace secrets zengarden.space/role=system
```

Application namespaces are discovered automatically from ArgoCD Applications - no labels needed.

### 3. Create Users

Example users are available in `examples/sample-user.yaml`:

```bash
kubectl apply -f examples/sample-user.yaml
```

Or create a single user:

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

### 4. Verify Deployment

```bash
# Check operator
kubectl get pods -n rbac-system -l app.kubernetes.io/name=rbac-operator

# List users
kubectl get users

# Check RoleBindings created
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=rbac-operator

# View user status
kubectl get user john-doe -o yaml
```

## Role Mapping

| User Role            | Namespaces                          | Permissions                          |
|----------------------|-------------------------------------|--------------------------------------|
| `app-developer`      | Application namespaces              | Read-only (view logs, exec pods)     |
| `platform-operator`  | Application + Platform              | CRUD workloads, manage ArgoCD apps   |
| `system-admin`       | Application + Platform + System     | Full access to all resources         |

## Quick Troubleshooting

**Operator not starting:**
```bash
kubectl logs -n rbac-system rbac-operator-0 -c rbac-service
```

**RoleBindings not created:**
```bash
# Check user status
kubectl get user <name> -o jsonpath='{.status.conditions[*].message}'

# Verify ClusterRoles exist
kubectl get clusterrole homelab:app-developer
kubectl get clusterrole homelab:platform-operator
kubectl get clusterrole homelab:system-admin
```

**Test user access:**
```bash
kubectl auth can-i get pods -n dev-retroboard --as=user@example.com
```

## Common Operations

**Update user roles:**
```bash
kubectl edit user john-doe
```

**Disable user:**
```bash
kubectl patch user john-doe --type=merge -p '{"spec":{"enabled":false}}'
```

**Delete user:**
```bash
kubectl delete user john-doe
```

**Force reconciliation:**
```bash
kubectl rollout restart statefulset/rbac-operator -n rbac-system
```

## Documentation

For detailed information, see:
- **[RBAC Operator Documentation](../../../../docs/content/operations/rbac-operator.mdx)** - Complete guide
- **[RBAC Documentation](../../../../docs/content/operations/rbac.mdx)** - Overall RBAC architecture
- **[README](README.md)** - Quick reference

## Architecture

```
User CRD → RBAC Operator → Discovers Namespaces → Creates RoleBindings
           (watches)        (ArgoCD + labels)      (per user/role/namespace)
```

The operator:
1. Watches User CRDs, ArgoCD Applications, and Namespaces
2. Discovers application namespaces from ArgoCD
3. Discovers platform/system namespaces from labels
4. Creates per-user RoleBindings: `homelab:<role>:<username>`
5. Reconciles every 5 minutes

## Security

- Non-root (UID 64535)
- Read-only filesystem
- Minimal RBAC permissions
- No secret access
- Auditable changes via User status
