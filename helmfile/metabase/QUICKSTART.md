# Metabase CNPG Operator - Quick Start

## What This Does

Automatically syncs all CloudNativePG databases to Metabase for analytics and visualization.

## Quick Deploy

1. **Set admin credentials:**
   ```bash
   cd helmfile/metabase
   cp env.yaml.template env.yaml
   # Edit env.yaml and set your Metabase admin email/password
   ```

2. **Deploy everything:**
   ```bash
   helmfile apply
   ```

3. **Access Metabase:**
   - URL: https://metabase.homelab.int.zengarden.space
   - Login with credentials from env.yaml

4. **Verify sync:**
   ```bash
   # Check operator logs
   kubectl logs -n metabase -l app.kubernetes.io/name=metabase-cnpg-operator -f
   
   # Should see logs like:
   # Processing database: dev-retroboard-api/retroboard-db
   # Successfully created database 'dev-retroboard-api/retroboard'
   ```

## How It Works

The operator watches for CNPG Database resources and automatically:
- Discovers database connection details from CNPG Cluster
- Reads credentials from Kubernetes secrets
- Creates/updates database connections in Metabase
- Runs every 5 minutes + event-driven on database changes

## Testing

Create a test database:
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: test-db
  namespace: default
spec:
  cluster:
    name: my-cluster
  name: testdb
  owner: testuser
```

Within seconds, you should see `default/testdb` appear in Metabase!

## Troubleshooting

**Operator not starting:**
```bash
kubectl describe pod -n metabase -l app.kubernetes.io/name=metabase-cnpg-operator
```

**Databases not syncing:**
```bash
# Check if operator can access CNPG resources
kubectl auth can-i get databases.postgresql.cnpg.io \
  --as=system:serviceaccount:metabase:metabase-cnpg-operator

# Force re-sync
kubectl rollout restart deployment/metabase-cnpg-operator -n metabase
```

**See full README.md for detailed documentation**

