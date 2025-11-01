# Grafana Alert Operator - Complete Setup

## Overview

This document describes the complete Grafana Alert Operator setup, including automatic service account provisioning.

## Architecture

The setup consists of two Helm charts deployed in sequence:

1. **grafana-service-account** - Provisions Grafana service account and stores token in K8s Secret
2. **grafana-alert-operator** - Manages Grafana alerts via Kubernetes CRDs

```
┌─────────────────────────────────────────────────────────────────┐
│                    Victoria Metrics Helmfile                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ├─── Deploys ───┐
                              │               │
                              ▼               ▼
        ┌──────────────────────────┐   ┌──────────────────────────┐
        │ grafana-service-account  │   │  grafana-alert-operator  │
        │      (Helm Chart)        │   │      (Helm Chart)        │
        └──────────────────────────┘   └──────────────────────────┘
                    │                              │
                    │ 1. Post-install Job          │ 2. Reads Secret
                    │                              │
                    ▼                              ▼
        ┌──────────────────────────┐   ┌──────────────────────────┐
        │   Grafana API            │   │  grafana-operator-token  │
        │   - Create SA            │   │     (K8s Secret)         │
        │   - Generate Token       │◄──│  - token                 │
        └──────────────────────────┘   │  - url                   │
                    │                  │  - orgId                 │
                    │ 3. Store         └──────────────────────────┘
                    ▼
        ┌──────────────────────────┐
        │  grafana-operator-token  │
        │     (K8s Secret)         │
        │  - token: glsa_xxx       │
        │  - url: http://...       │
        │  - orgId: 1              │
        └──────────────────────────┘
                    │
                    │ 4. Used by Operator
                    ▼
        ┌──────────────────────────┐
        │   Operator Pod           │
        │   - Watches CRDs         │
        │   - Syncs with Grafana   │
        └──────────────────────────┘
```

## Components Created

### 1. Grafana Service Account Chart

**Location**: `charts/grafana-service-account/`

**Purpose**: Automatically provisions Grafana service account and token

**Files**:
- `Chart.yaml` - Helm chart metadata
- `values.yaml` - Configuration (Grafana URL, admin credentials, etc.)
- `templates/job.yaml` - Post-install Job that creates SA and token
- `templates/rbac.yaml` - Permissions for Job
- `templates/serviceaccount.yaml` - K8s ServiceAccount for Job
- `README.md` - Documentation

**What it does**:
1. Runs as Helm post-install/post-upgrade hook
2. Waits for Grafana to be ready
3. Creates service account in Grafana (if not exists)
4. Generates API token
5. Stores token in Kubernetes Secret (`grafana-operator-token`)

### 2. Grafana Alert Operator

**Location**: `grafana-alert-operator/`

**Purpose**: Manages Grafana alerts via Kubernetes CRDs

**Files**:
- `Chart.yaml` - Helm chart metadata
- `values.yaml` - Operator configuration
- `crds/` - 4 Custom Resource Definitions
  - `grafanaalertrule-crd.yaml`
  - `grafananotificationpolicy-crd.yaml`
  - `grafanamutetiming-crd.yaml`
  - `grafananotificationtemplate-crd.yaml`
- `files/` - Operator implementation
  - `grafana-alert-handler.sh` - Shell-operator hook
  - `grafana-alert-service.py` - Python reconciliation service
  - `requirements.txt` - Python dependencies
- `templates/` - Kubernetes resources
  - `statefulset.yaml` - Operator deployment
  - `rbac.yaml` - Cluster permissions
  - `serviceaccount.yaml` - K8s ServiceAccount
  - `hooks-configmap.yaml` - Shell hook config
  - `handler-service-configmap.yaml` - Python service config
- `examples/complete-example.yaml` - Example CRDs
- `README.md` - User documentation
- `DEPLOYMENT.md` - Deployment guide

**What it does**:
1. Watches for CRD changes (AlertRule, NotificationPolicy, etc.)
2. Reads Grafana credentials from Secret
3. Reconciles CRDs with Grafana via HTTP API
4. Updates CRD status with sync results

## Deployment Flow

### 1. Initial Deployment

```bash
cd /Users/oleksiyp/dev/homelab/platform/helmfile/victoria-metrics

# Deploy everything
helmfile sync
```

**What happens**:
1. Victoria Metrics stack deployed (includes Grafana)
2. `grafana-service-account` chart deployed:
   - Job waits for Grafana to be ready
   - Creates service account `kubernetes-alert-operator` with Editor role
   - Generates token
   - Creates Secret `grafana-operator-token` in `monitoring` namespace
3. `grafana-alert-operator` chart deployed:
   - Applies 4 CRDs
   - Deploys StatefulSet with shell-operator + Python service
   - Operator starts watching for CRDs

### 2. Verify Deployment

```bash
# Check service account job completed
kubectl get jobs -n monitoring | grep grafana-service-account
# Expected: grafana-service-account-provision   1/1   XXs

# Check secret was created
kubectl get secret grafana-operator-token -n monitoring
# Expected: grafana-operator-token   Opaque   3   XXs

# Check operator is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana-alert-operator
# Expected: grafana-alert-operator-0   2/2   Running

# Check operator logs
kubectl logs -n monitoring grafana-alert-operator-0 -c handler-service --tail=20
# Expected: "Grafana Alert Operator Service initialized"
#           "Starting service loop..."
```

## Configuration

### Grafana Service Account Chart

Located in victoria-metrics helmfile:

```yaml
# helmfile.yaml.gotmpl
- name: grafana-service-account
  namespace: monitoring
  chart: ./charts/grafana-service-account
  needs:
    - victoria-metrics/vm
  values:
    - grafana:
        url: "http://vm-grafana.victoria-metrics.svc.cluster.local"
        orgId: 1
        adminSecretName: "vm-grafana"
        adminUserKey: "admin-user"
        adminPasswordKey: "admin-password"
      serviceAccount:
        name: "kubernetes-alert-operator"
        role: "Editor"
      secret:
        name: "grafana-operator-token"
        namespace: "monitoring"
```

**Key Settings**:
- `grafana.url` - Internal Grafana service URL
- `grafana.adminSecretName` - Secret containing Grafana admin credentials
- `serviceAccount.role` - `Editor` (recommended), `Admin`, or `Viewer`
- `secret.namespace` - Where to create the token Secret (default: release namespace)

### Grafana Alert Operator Chart

Located in victoria-metrics helmfile:

```yaml
# helmfile.yaml.gotmpl
- name: grafana-alert-operator
  namespace: monitoring
  chart: ./grafana-alert-operator
  needs:
    - monitoring/grafana-service-account
  values:
    - persistence:
        enabled: true
        size: 200Mi
      resources:
        requests:
          memory: 128Mi
          cpu: 100m
        limits:
          memory: 512Mi
          cpu: 500m
```

## Usage Examples

### Create an Alert Rule

```bash
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.zengarden.space/v1
kind: GrafanaAlertRule
metadata:
  name: high-cpu-alert
  namespace: monitoring
spec:
  grafanaRef:
    secretRef:
      name: grafana-operator-token
      namespace: monitoring

  folderUID: "general"
  ruleGroup: "System Alerts"

  title: "High CPU Usage"
  condition: "C"
  noDataState: "NoData"
  execErrState: "Alerting"
  for: "5m"

  annotations:
    summary: "CPU usage is above 80%"
    description: "CPU usage has been above 80% for more than 5 minutes"

  labels:
    severity: "warning"

  data:
    - refId: "A"
      queryType: "prometheus"
      relativeTimeRange:
        from: 600
        to: 0
      datasourceUid: "prometheus"
      model:
        expr: '100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'

    - refId: "C"
      queryType: "math"
      relativeTimeRange:
        from: 600
        to: 0
      model:
        expression: "\$A > 80"
EOF
```

### Check Status

```bash
# List all alert rules
kubectl get grafanaalertrules -A

# Check specific alert rule
kubectl get grafanaalertrule high-cpu-alert -n monitoring -o yaml

# View sync status
kubectl get grafanaalertrule high-cpu-alert -n monitoring \
  -o jsonpath='{.status.syncStatus}'
```

### Verify in Grafana UI

1. Open Grafana: https://grafana.homelab.int.{domain}
2. Navigate to: **Alerting → Alert rules**
3. Look for "System Alerts" rule group
4. Verify "High CPU Usage" alert exists

## Troubleshooting

### Service Account Job Failed

```bash
# Check job logs
kubectl logs -n monitoring job/grafana-service-account-provision \
  -c provision-service-account

# Common issues:
# - Grafana not ready: Increase wait time or check Grafana pod status
# - Auth error: Verify admin secret name and keys
# - Connection refused: Check Grafana service name/namespace
```

### Operator Not Syncing Alerts

```bash
# Check operator logs
kubectl logs -n monitoring grafana-alert-operator-0 -c handler-service

# Check if secret exists and is readable
kubectl get secret grafana-operator-token -n monitoring
kubectl describe secret grafana-operator-token -n monitoring

# Test Grafana API from operator pod
kubectl exec -n monitoring grafana-alert-operator-0 -c handler-service -it -- sh
# Inside pod:
apk add curl
TOKEN=$(cat /path/to/token)  # Extract from secret
curl -H "Authorization: Bearer $TOKEN" http://vm-grafana.victoria-metrics.svc/api/health
```

### Alert Rule Status Shows "Failed"

```bash
# Check detailed status
kubectl describe grafanaalertrule <name> -n <namespace>

# Common errors:
# - "folder not found": Verify folderUID exists in Grafana
# - "datasource not found": Check datasourceUid is correct
# - "unauthorized": Token may have expired or been revoked
```

## Token Rotation

To rotate the Grafana API token:

```bash
# Option 1: Re-run the service account job
kubectl delete job grafana-service-account-provision -n monitoring
helmfile -l name=grafana-service-account sync

# Option 2: Manual rotation
# 1. In Grafana UI: Delete old token
# 2. Generate new token
# 3. Update secret:
kubectl create secret generic grafana-operator-token \
  --namespace monitoring \
  --from-literal=token='NEW_TOKEN' \
  --from-literal=url='http://...' \
  --from-literal=orgId='1' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Upgrading

### Upgrade Charts

```bash
cd /Users/oleksiyp/dev/homelab/platform/helmfile/victoria-metrics

# Pull latest code
git pull

# Apply upgrades
helmfile sync
```

### Upgrade CRDs

CRDs are not automatically upgraded by Helm. To upgrade manually:

```bash
kubectl apply -f grafana-alert-operator/crds/
```

## Uninstalling

### Remove Operator

```bash
# Remove from helmfile or set installed: false
helmfile -l name=grafana-alert-operator destroy
helmfile -l name=grafana-service-account destroy
```

### Clean Up CRDs

**WARNING**: This deletes all alert rules!

```bash
kubectl delete crd grafanaalertrules.monitoring.zengarden.space
kubectl delete crd grafananotificationpolicies.monitoring.zengarden.space
kubectl delete crd grafanamutetimings.monitoring.zengarden.space
kubectl delete crd grafananotificationtemplates.monitoring.zengarden.space
```

### Clean Up Grafana

Alerts created by the operator remain in Grafana after uninstall. Clean up manually via Grafana UI or API.

## Security Notes

- **Service account Job** requires admin credentials temporarily (only during execution)
- **Operator** only needs read access to Secrets (cannot create/modify them)
- **Token permissions**: Editor role recommended (minimum required for alert management)
- **Secret encryption**: Enable Kubernetes encryption-at-rest for Secret protection
- **Token expiration**: Set `token.secondsToLive` for automatic expiration (0 = never)

## Next Steps

1. Deploy example alerts from `grafana-alert-operator/examples/`
2. Configure notification policies for alert routing
3. Set up mute timings for maintenance windows
4. Integrate with your GitOps workflow (ArgoCD)

## References

- [Grafana Alert Operator README](./grafana-alert-operator/README.md)
- [Grafana Service Account Chart README](./charts/grafana-service-account/README.md)
- [Deployment Guide](./grafana-alert-operator/DEPLOYMENT.md)
- [Grafana Alerting API Docs](https://grafana.com/docs/grafana/latest/alerting/)
