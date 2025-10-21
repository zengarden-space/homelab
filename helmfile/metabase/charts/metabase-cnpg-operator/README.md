# Metabase CNPG Operator

A shell-operator based Kubernetes operator that automatically syncs CloudNativePG (CNPG) Database resources to Metabase.

## Features

- **Event-driven synchronization**: Automatically detects when CNPG Database resources are created or modified
- **Periodic reconciliation**: Runs every 5 minutes to ensure all databases are synced
- **Automatic credential management**: Reads database credentials from CNPG managed role secrets
- **SSL/TLS support**: Configures Metabase connections with SSL enabled
- **Namespace-aware**: Creates unique database names in Metabase using `namespace/database` format

## How it works

The operator watches for `databases.postgresql.cnpg.io` resources across all namespaces. When a database is created or modified:

1. Retrieves the CNPG Cluster details to get connection information
2. Reads the database owner credentials from the associated secret
3. Constructs the connection details (host, port, database name)
4. Calls the Metabase API to create or update the database connection
5. Configures automatic metadata sync and caching in Metabase

## Configuration

### Required Values

You must set the Metabase admin credentials in `env.yaml`:

```yaml
metabase:
  adminEmail: "admin@example.com"
  adminPassword: "your-secure-password"
```

### Optional Values

```yaml
# Metabase service URL (default: http://metabase.metabase.svc.cluster.local)
metabase:
  url: "http://metabase.metabase.svc.cluster.local"

# Resource limits
resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

## Database Naming

Databases are registered in Metabase with the format: `namespace/database-name`

For example:
- `dev-retroboard-api/retroboard` 
- `prod-retroboard-api/retroboard`

This ensures databases from different namespaces don't conflict.

## RBAC Permissions

The operator requires the following cluster-level permissions:

- **CNPG resources**: Read access to `databases.postgresql.cnpg.io` and `clusters.postgresql.cnpg.io`
- **Secrets**: Read access to secrets containing database credentials
- **ConfigMaps**: Read/write for shell-operator internal state

## Troubleshooting

### Check operator logs

```bash
kubectl logs -n metabase -l app.kubernetes.io/name=metabase-cnpg-operator -f
```

### Verify CNPG resources

```bash
kubectl get databases.postgresql.cnpg.io -A
kubectl get clusters.postgresql.cnpg.io -A
```

### Test Metabase API access

```bash
kubectl exec -n metabase deployment/metabase-cnpg-operator -- \
  curl -s http://metabase.metabase.svc.cluster.local/api/health
```

## Architecture

This operator uses [shell-operator](https://github.com/flant/shell-operator) which:
- Handles Kubernetes API watching and event processing
- Provides automatic leader election for HA
- Manages hook lifecycle and retries
- Exposes metrics for monitoring

The actual sync logic is implemented in a simple bash script (`hooks/sync-cnpg-databases.sh`) that:
- Processes Kubernetes events
- Calls kubectl to gather resource information
- Uses curl to interact with the Metabase API
- Handles authentication and session management

## Manual Sync

To trigger an immediate sync without waiting for the schedule:

```bash
kubectl delete pod -n metabase -l app.kubernetes.io/name=metabase-cnpg-operator
```

The operator will restart and perform a full reconciliation on startup.

