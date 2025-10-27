# Metabase Deployment

This helmfile deploys Metabase with an automatic CNPG database sync operator.

## Components

1. **Metabase**: Open-source business intelligence and analytics platform
2. **Metabase CNPG Operator**: Shell-operator based controller that automatically syncs CloudNativePG databases to Metabase

## Features

- **Secure deployment**: Non-root user, read-only root filesystem, security context constraints
- **Persistent storage**: H2 database with persistent volume for data storage
- **TLS/SSL**: Automatic HTTPS via cert-manager with Let's Encrypt
- **Ingress**: Accessible at `https://metabase.homelab.int.zengarden.space`
- **Automatic database discovery**: CNPG databases are automatically added to Metabase

## Prerequisites

- Kubernetes cluster with:
  - cert-manager (for TLS certificates)
  - ingress-nginx (for ingress)
  - CloudNativePG operator (for PostgreSQL databases)

## Configuration

### 1. Set up credentials

Copy the template and fill in the values:

```bash
cp env.yaml.template env.yaml
```

Edit `env.yaml`:

```yaml
metabase:
  adminEmail: "your-email@example.com"
  adminPassword: "your-secure-password"
```

**Important**: Keep `env.yaml` secure and don't commit it to version control!

### 2. Deploy

```bash
cd helmfile/metabase
helmfile apply
```

## How the Operator Works

The Metabase CNPG Operator automatically:

1. **Watches** for `databases.postgresql.cnpg.io` resources across all namespaces
2. **Detects** when databases are created or modified
3. **Retrieves** connection details from the CNPG Cluster resource
4. **Reads** database credentials from Kubernetes secrets
5. **Syncs** the database connection to Metabase via its REST API
6. **Configures** automatic metadata sync and caching

### Database Naming Convention

Databases appear in Metabase with the format: `namespace/database-name`

Examples:
- `dev-retroboard-api/retroboard`
- `prod-retroboard-api/retroboard`

This prevents naming conflicts between databases in different namespaces.

## Accessing Metabase

Once deployed, access Metabase at:
- **URL**: https://metabase.homelab.int.zengarden.space
- **Admin email**: The email you configured in `env.yaml`
- **Admin password**: The password you configured in `env.yaml`

## Initial Setup

On first login, Metabase will ask you to:
1. Set up your admin account (use the credentials from `env.yaml`)
2. Add a database (skip this - the operator will do it automatically)
3. Configure your preferences

After setup, the operator will automatically discover and add all CNPG databases.

## Monitoring

### Check Metabase logs

```bash
kubectl logs -n metabase -l app.kubernetes.io/name=metabase -f
```

### Check operator logs

```bash
kubectl logs -n metabase -l app.kubernetes.io/name=metabase-cnpg-operator -f
```

### Verify databases are synced

```bash
# Check CNPG databases
kubectl get databases.postgresql.cnpg.io -A

# Check operator events
kubectl get events -n metabase --sort-by='.lastTimestamp'
```

## Troubleshooting

### Metabase won't start

1. Check pod status: `kubectl get pods -n metabase`
2. Check logs: `kubectl logs -n metabase -l app.kubernetes.io/name=metabase`
3. Common issues:
   - Database file permissions (should be owned by UID 2000)
   - Insufficient storage

### Operator not syncing databases

1. Check operator logs: `kubectl logs -n metabase -l app.kubernetes.io/name=metabase-cnpg-operator`
2. Verify RBAC permissions: `kubectl auth can-i get databases.postgresql.cnpg.io --as=system:serviceaccount:metabase:metabase-cnpg-operator`
3. Test Metabase API access:
   ```bash
   kubectl run -n metabase curl-test --rm -it --restart=Never --image=curlimages/curl -- \
     curl -v http://metabase.metabase.svc.cluster.local/api/health
   ```

### Database not appearing in Metabase

1. Check if the database exists: `kubectl get databases.postgresql.cnpg.io -A`
2. Check if credentials secret exists: `kubectl get secret <owner-name> -n <namespace>`
3. Force a sync by restarting the operator: `kubectl rollout restart deployment/metabase-cnpg-operator -n metabase`
4. Check operator logs for errors

### Manual database addition

If you need to manually add a database:

1. Get connection details:
   ```bash
   kubectl get cluster.postgresql.cnpg.io <cluster-name> -n <namespace> -o yaml
   ```

2. Get credentials:
   ```bash
   kubectl get secret <owner-secret> -n <namespace> -o jsonpath='{.data.username}' | base64 -d
   kubectl get secret <owner-secret> -n <namespace> -o jsonpath='{.data.password}' | base64 -d
   ```

3. Add in Metabase UI:
   - Go to Settings → Admin → Databases → Add database
   - Select PostgreSQL
   - Host: `<cluster-name>-rw.<namespace>.svc.cluster.local`
   - Port: `5432`
   - Database name: from `spec.name` in Database resource
   - Username/Password: from secret

## Upgrading

### Upgrade Metabase

Edit `helmfile.yaml.gotmpl` and change the version:

```yaml
chart: pmint93/metabase
version: 2.22.2  # Update this
```

Then apply:

```bash
helmfile apply
```

### Upgrade Operator

The operator uses shell-operator image. To upgrade:

Edit `charts/metabase-cnpg-operator/values.yaml`:

```yaml
image:
  repository: flant/shell-operator
  tag: v1.4.10  # Update this
```

Then apply:

```bash
helmfile apply
```

## Uninstalling

```bash
helmfile destroy
```

This will remove Metabase and the operator, but preserve the persistent volume with your data.

To also delete the persistent volume:

```bash
kubectl delete pvc -n metabase metabase-database
```

## Security Considerations

- **Credentials**: Store `env.yaml` securely (e.g., encrypted with SOPS or external-secrets)
- **Network policies**: Consider adding network policies to restrict access
- **RBAC**: The operator has cluster-wide read access to CNPG resources and secrets
- **Metabase admin**: Change the default admin password after first login
- **Database access**: The operator uses database owner credentials (full access)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │              Metabase Namespace                   │  │
│  │                                                    │  │
│  │  ┌──────────────┐         ┌──────────────────┐  │  │
│  │  │   Metabase   │◄────────│  CNPG Operator   │  │  │
│  │  │              │  Syncs  │                   │  │  │
│  │  │  (H2 DB)     │  DBs    │ (shell-operator) │  │  │
│  │  └──────┬───────┘         └────────▲─────────┘  │  │
│  │         │                           │             │  │
│  │         │ PVC                       │ Watches     │  │
│  │         ▼                           │             │  │
│  │  ┌──────────────┐                  │             │  │
│  │  │ Persistent   │                  │             │  │
│  │  │   Volume     │                  │             │  │
│  │  └──────────────┘                  │             │  │
│  └────────────────────────────────────┼─────────────┘  │
│                                        │                │
│  ┌─────────────────────────────────────┼──────────────┐ │
│  │        App Namespaces               │              │ │
│  │                                     │              │ │
│  │  ┌──────────────────┐               │              │ │
│  │  │ CNPG Cluster     │               │              │ │
│  │  │ (PostgreSQL)     │               │              │ │
│  │  └────────┬─────────┘               │              │ │
│  │           │                         │              │ │
│  │  ┌────────▼─────────┐               │              │ │
│  │  │ CNPG Database    │───────────────┘              │ │
│  │  │ (CRD)            │  Watched by operator         │ │
│  │  └──────────────────┘                              │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## References

- [Metabase Documentation](https://www.metabase.com/docs/latest/)
- [Metabase API](https://www.metabase.com/docs/latest/api-documentation.html)
- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [Shell-operator](https://github.com/flant/shell-operator)

