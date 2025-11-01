# Grafana Service Account Provisioner

Helm chart that provisions a Grafana service account and stores the API token in a Kubernetes Secret for use by the Grafana Alert Operator.

## Overview

This chart runs as a Helm post-install/post-upgrade hook to:

1. Wait for Grafana to be ready
2. Create a service account in Grafana (if not exists)
3. Generate an API token for the service account
4. Store the token in a Kubernetes Secret

## Prerequisites

- Grafana must be deployed and accessible
- Grafana admin credentials must be available in a Kubernetes Secret

## Installation

This chart is automatically deployed as part of the victoria-metrics helmfile.

```bash
cd /Users/oleksiyp/dev/homelab/platform/helmfile/victoria-metrics
helmfile sync
```

## Configuration

### Required Configuration

Update `values.yaml` to match your Grafana deployment:

```yaml
grafana:
  # Internal cluster URL to Grafana
  url: "http://vmetrics-grafana.monitoring.svc.cluster.local"

  # Organization ID (usually 1 for default org)
  orgId: 1

  # Secret containing admin credentials
  adminSecretName: "vmetrics-grafana"
  adminUserKey: "admin-user"
  adminPasswordKey: "admin-password"

serviceAccount:
  # Name of service account to create in Grafana
  name: "kubernetes-alert-operator"

  # Role: Editor (recommended), Admin, or Viewer
  role: "Editor"

secret:
  # Name of Kubernetes Secret to create
  name: "grafana-operator-token"

  # Namespace (defaults to release namespace)
  namespace: ""
```

### Values Explained

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana.url` | Internal Grafana service URL | `http://vmetrics-grafana.monitoring.svc.cluster.local` |
| `grafana.orgId` | Grafana organization ID | `1` |
| `grafana.adminSecretName` | Secret with admin credentials | `vmetrics-grafana` |
| `grafana.adminUserKey` | Key for admin username | `admin-user` |
| `grafana.adminPasswordKey` | Key for admin password | `admin-password` |
| `serviceAccount.name` | Service account name in Grafana | `kubernetes-alert-operator` |
| `serviceAccount.role` | Service account role | `Editor` |
| `secret.name` | K8s Secret name to create | `grafana-operator-token` |
| `secret.namespace` | Secret namespace (empty = release ns) | `""` |
| `token.name` | Token display name in Grafana | `k8s-operator-token` |
| `token.secondsToLive` | Token expiration (0 = never) | `0` |

## How It Works

### Job Execution Flow

1. **Init Container** (`provision-service-account`):
   - Waits for Grafana health endpoint to respond (max 5 minutes)
   - Checks if service account already exists via API
   - Creates service account if needed
   - Generates new API token
   - Writes token to shared volume

2. **Main Container** (`create-secret`):
   - Reads token from shared volume
   - Creates/updates Kubernetes Secret with:
     - `token`: Grafana API token
     - `url`: Grafana URL
     - `orgId`: Organization ID

### RBAC Strategy

The chart intelligently chooses RBAC scope:

- **Same namespace**: Uses `Role` + `RoleBinding` (namespace-scoped)
- **Different namespace**: Uses `ClusterRole` + `ClusterRoleBinding` (cluster-scoped)

This allows flexibility in Secret placement while maintaining least-privilege.

## Usage

### Verify Deployment

```bash
# Check job completed successfully
kubectl get jobs -n monitoring | grep grafana-service-account

# View job logs
kubectl logs -n monitoring job/grafana-service-account-provision -c provision-service-account
kubectl logs -n monitoring job/grafana-service-account-provision -c create-secret

# Verify Secret was created
kubectl get secret grafana-operator-token -n monitoring
kubectl get secret grafana-operator-token -n monitoring -o jsonpath='{.data.token}' | base64 -d
```

### Secret Structure

The created Secret contains:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-operator-token
  namespace: monitoring
type: Opaque
data:
  token: <base64-encoded-grafana-token>
  url: <base64-encoded-grafana-url>
  orgId: <base64-encoded-org-id>
```

### Using with Grafana Alert Operator

Reference the Secret in your `GrafanaAlertRule` CRDs:

```yaml
apiVersion: monitoring.zengarden.space/v1
kind: GrafanaAlertRule
metadata:
  name: my-alert
spec:
  grafanaRef:
    secretRef:
      name: grafana-operator-token
      namespace: monitoring
  # ... rest of alert rule spec
```

## Troubleshooting

### Job fails with "Grafana not ready"

```bash
# Check Grafana pod is running
kubectl get pods -n monitoring | grep grafana

# Check Grafana service
kubectl get svc -n monitoring | grep grafana

# Test connectivity from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://vmetrics-grafana.monitoring.svc.cluster.local/api/health
```

**Fix**: Ensure `grafana.url` matches actual Grafana service name.

### Job fails with authentication error

```bash
# Check admin secret exists
kubectl get secret vmetrics-grafana -n monitoring

# Verify keys
kubectl get secret vmetrics-grafana -n monitoring -o jsonpath='{.data}' | jq
```

**Fix**: Ensure `adminSecretName`, `adminUserKey`, and `adminPasswordKey` match your Grafana deployment.

### Service account already exists but token creation fails

This can happen if the service account was created manually or by a previous run.

```bash
# Check Grafana logs for errors
kubectl logs -n monitoring <grafana-pod-name>

# View existing service accounts in Grafana UI
# Navigate to: Administration → Users and access → Service Accounts
```

**Fix**: Delete the service account in Grafana UI and re-run the job.

### Secret not created

```bash
# Check create-secret container logs
kubectl logs -n monitoring job/grafana-service-account-provision -c create-secret

# Check RBAC permissions
kubectl auth can-i create secrets --as=system:serviceaccount:monitoring:grafana-service-account -n monitoring
```

**Fix**: Verify ServiceAccount has permissions to create Secrets in target namespace.

## Token Rotation

To rotate the token:

```bash
# Delete the job (triggers re-creation on next helmfile sync)
kubectl delete job grafana-service-account-provision -n monitoring

# Re-run helmfile sync
helmfile sync
```

Or manually:

1. Delete old token in Grafana UI
2. Re-run the job:
   ```bash
   helm upgrade grafana-service-account ./charts/grafana-service-account \
     --namespace monitoring --reuse-values
   ```

## Security Considerations

- **Admin credentials**: Job requires admin credentials temporarily to create service account
- **Token storage**: Token stored in Kubernetes Secret (encrypted at rest if enabled)
- **Token scope**: Use `Editor` role for operator (minimum required permissions)
- **Token expiration**: Default is no expiration (set `token.secondsToLive` for rotation policy)
- **Job cleanup**: Job pods are automatically deleted after completion (`deletePolicy: before-hook-creation`)

## Development

### Testing Locally

```bash
# Dry-run to see generated manifests
helm template grafana-service-account ./charts/grafana-service-account \
  --namespace monitoring

# Install for testing
helm install grafana-service-account ./charts/grafana-service-account \
  --namespace monitoring

# Check job status
kubectl get jobs -n monitoring
kubectl describe job grafana-service-account-provision -n monitoring
```

### Customizing for Other Grafana Instances

Create a custom values file:

```yaml
# custom-values.yaml
grafana:
  url: "https://grafana.example.com"
  orgId: 2
  adminSecretName: "grafana-prod-admin"

secret:
  name: "grafana-prod-operator-token"
  namespace: "prod"
```

Deploy:

```bash
helm upgrade --install grafana-service-account ./charts/grafana-service-account \
  --namespace monitoring \
  --values custom-values.yaml
```

## References

- [Grafana Service Account API](https://grafana.com/docs/grafana/latest/developers/http_api/serviceaccount/)
- [Helm Hooks Documentation](https://helm.sh/docs/topics/charts_hooks/)
- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
