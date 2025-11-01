# Grafana Alert Operator - Deployment Guide

## Overview

This guide walks through deploying the Grafana Alert Operator in your homelab Kubernetes cluster.

## Prerequisites

- Kubernetes cluster (ARM64 compatible)
- Grafana instance deployed and accessible
- `kubectl` and `helmfile` installed
- Access to create cluster-wide resources (CRDs, ClusterRole)

## Deployment Steps

### 1. Prepare Grafana Service Account

The operator requires a Grafana service account token to interact with the Grafana API.

**Option A: Automated (Recommended)**

Add a post-install Job to your Grafana Helm chart that creates the service account and stores the token in a Secret. See the main design document for the Job template.

**Option B: Manual**

1. Log into Grafana UI
2. Navigate to: `Administration → Users and access → Service Accounts`
3. Click "Add service account"
   - Name: `kubernetes-alert-operator`
   - Role: `Editor` (or `Admin` if managing contact points)
4. Click "Add service account token"
   - Display name: `k8s-operator-token`
   - Expiration: No expiration (or set according to your security policy)
5. Copy the generated token (starts with `glsa_`)

6. Create Kubernetes Secret:

```bash
kubectl create namespace monitoring  # if not exists

kubectl create secret generic grafana-operator-token \
  --namespace monitoring \
  --from-literal=token='glsa_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
  --from-literal=url='http://grafana.monitoring.svc.cluster.local:3000' \
  --from-literal=orgId='1'
```

### 2. Deploy Operator

```bash
cd /Users/oleksiyp/dev/homelab/platform/helmfile/victoria-metrics

# Preview changes
helmfile -f grafana-alert-operator/helmfile.yaml.gotmpl diff

# Deploy
helmfile -f grafana-alert-operator/helmfile.yaml.gotmpl sync
```

### 3. Verify Deployment

```bash
# Check CRDs are installed
kubectl get crd | grep monitoring.zengarden.space

# Expected output:
# grafanaalertrules.monitoring.zengarden.space
# grafanamutetimings.monitoring.zengarden.space
# grafananotificationpolicies.monitoring.zengarden.space
# grafananotificationtemplates.monitoring.zengarden.space

# Check operator pod is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana-alert-operator

# Check logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana-alert-operator -c handler-service --tail=50

# Expected output should include:
# "Grafana Alert Operator Service initialized"
# "Starting service loop..."
```

### 4. Test with Example Alert

```bash
# Apply example alert rule
kubectl apply -f grafana-alert-operator/examples/complete-example.yaml

# Check alert rule status
kubectl get grafanaalertrules -n monitoring

# View detailed status
kubectl describe grafanaalertrule high-cpu-alert -n monitoring

# Check if alert appears in Grafana
# Navigate to: Grafana UI → Alerting → Alert rules → System Alerts
```

## Configuration

### Custom Grafana Instance

To use a different Grafana instance, create a separate Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: prod-grafana-token
  namespace: prod
type: Opaque
stringData:
  token: "glsa_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  url: "https://grafana.prod.example.com"
  orgId: "2"
```

Then reference it in your CRDs:

```yaml
spec:
  grafanaRef:
    secretRef:
      name: prod-grafana-token
      namespace: prod
```

### Resource Limits

Adjust resource limits in `values.yaml` if needed:

```yaml
resources:
  requests:
    memory: 256Mi  # Increase for large environments
    cpu: 200m
  limits:
    memory: 1Gi
    cpu: 1000m
```

### Persistence

By default, the operator uses a 200Mi PVC to cache pip packages. To disable:

```yaml
persistence:
  enabled: false
```

## Troubleshooting

### Operator pod not starting

```bash
# Check pod events
kubectl describe pod -n monitoring -l app.kubernetes.io/name=grafana-alert-operator

# Common issues:
# - PVC not binding: Check StorageClass availability
# - Image pull errors: Check internet connectivity (for Alpine/Shell-operator images)
```

### Alert rule not syncing

```bash
# Check operator logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana-alert-operator -c handler-service

# Check CRD status
kubectl get grafanaalertrule <name> -n <namespace> -o yaml

# Common issues:
# - Authentication error: Verify Secret exists and token is valid
# - Folder not found: Verify folderUID exists in Grafana
# - Datasource not found: Verify datasourceUid is correct
```

### Status stuck at "Pending"

```bash
# Check if handler service is processing requests
kubectl exec -n monitoring -it <pod-name> -c handler-service -- ls -la /shared

# Should see request/response files being created and deleted
# If no files, shell-operator might not be triggering hooks

# Check shell-operator logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana-alert-operator -c shell-operator
```

### Connection refused to Grafana

```bash
# Test connectivity from operator pod
kubectl exec -n monitoring -it <pod-name> -c handler-service -- sh
# Inside pod:
apk add curl
curl -H "Authorization: Bearer <token>" http://grafana.monitoring.svc.cluster.local:3000/api/health

# If fails, check:
# - Grafana service name and namespace
# - Network policies
# - Grafana pod is running
```

## Upgrading

### Upgrade Operator

```bash
cd /Users/oleksiyp/dev/homelab/platform/helmfile/victoria-metrics

# Pull latest changes
git pull

# Apply upgrade
helmfile -f grafana-alert-operator/helmfile.yaml.gotmpl sync
```

**Note**: ConfigMap changes will automatically trigger pod restart due to checksum annotations.

### Upgrade CRDs

CRDs are not automatically upgraded by Helm. To upgrade CRDs:

```bash
kubectl apply -f grafana-alert-operator/crds/
```

## Uninstalling

### Remove Operator

```bash
helmfile -f grafana-alert-operator/helmfile.yaml.gotmpl destroy
```

### Remove CRDs (Optional)

**WARNING**: This will delete all alert rule CRs!

```bash
kubectl delete crd grafanaalertrules.monitoring.zengarden.space
kubectl delete crd grafananotificationpolicies.monitoring.zengarden.space
kubectl delete crd grafanamutetimings.monitoring.zengarden.space
kubectl delete crd grafananotificationtemplates.monitoring.zengarden.space
```

### Clean up Grafana

The operator does **not** automatically delete alerts from Grafana when uninstalled. To clean up:

1. Manually delete alerts in Grafana UI, or
2. Use Grafana API to delete provisioned alerts

## Security Considerations

### Token Permissions

- Use **Editor** role for read/write alert management
- Use **Viewer** role for read-only operations (status checking)
- Avoid using **Admin** role unless necessary

### Token Rotation

Rotate tokens regularly:

```bash
# 1. Create new token in Grafana
# 2. Update Secret
kubectl create secret generic grafana-operator-token \
  --namespace monitoring \
  --from-literal=token='NEW_TOKEN' \
  --from-literal=url='...' \
  --from-literal=orgId='1' \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Operator will use new token on next reconciliation (no restart needed)
```

### RBAC

The operator requires:
- **Cluster-wide read** on CRDs
- **Cluster-wide status update** on CRDs
- **Read-only access** to Secrets (for Grafana credentials)
- **No write access** to Secrets

### Network Policies

If using network policies, allow:
- Operator → Grafana API (TCP 3000 or 443)
- Operator → Kubernetes API server

## Next Steps

- Create alert rules for your applications
- Set up notification policies for alert routing
- Configure mute timings for maintenance windows
- Integrate with GitOps workflow (ArgoCD)

## Support

For issues or questions:
- Check logs: `kubectl logs -n monitoring -l app.kubernetes.io/name=grafana-alert-operator`
- Review CRD status: `kubectl describe grafanaalertrule <name>`
- Consult [Grafana API docs](https://grafana.com/docs/grafana/latest/alerting/)
