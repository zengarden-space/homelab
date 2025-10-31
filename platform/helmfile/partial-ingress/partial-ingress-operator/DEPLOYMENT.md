# PartialIngress Operator Deployment Guide

## Overview

The PartialIngress operator is deployed as part of the ingress-nginx helmfile in the homelab system.

## Architecture

```
homelab/platform/helmfile/partial-ingress/
├── helmfile.yaml.gotmpl           # Helmfile configuration
└── partial-ingress-operator/
    ├── Chart.yaml                 # Helm chart metadata
    ├── values.yaml                # Default values
    ├── README.md                  # Usage documentation
    ├── DEPLOYMENT.md              # This file
    ├── crds/
    │   ├── partialingress-crd.yaml
    │   └── compositeingresshost-crd.yaml
    ├── files/
    │   ├── partial-ingress-handler.sh       # Shell-operator hook
    │   ├── partial-ingress-service.py       # Python service
    │   └── requirements.txt                 # Python dependencies
    ├── templates/
    │   ├── _helpers.tpl
    │   ├── serviceaccount.yaml
    │   ├── rbac.yaml
    │   ├── hooks-configmap.yaml
    │   ├── handler-service-configmap.yaml
    │   ├── statefulset.yaml
    │   └── NOTES.txt
    └── examples/
        └── complete-example.yaml
```

## Deployment

### Prerequisites

1. Kubernetes cluster with ingress-nginx installed
2. Helmfile installed
3. kubectl access to the cluster

### Deploy via Helmfile

The operator is automatically deployed with the platform components:

```bash
cd /Users/oleksiyp/dev/homelab/platform/helmfile/partial-ingress

# Preview changes
helmfile diff

# Apply changes
helmfile sync
```

### Manual Deployment (for testing)

```bash
# Install CRDs first
kubectl apply -f partial-ingress-operator/crds/

# Install operator
helm install partial-ingress-operator ./partial-ingress-operator \
  --namespace ingress-nginx \
  --create-namespace
```

## Verification

### Check operator status

```bash
kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=partial-ingress-operator
```

Expected output:
```
NAME                                   READY   STATUS    RESTARTS   AGE
partial-ingress-operator-0             2/2     Running   0          1m
```

### Check CRDs

```bash
kubectl get crds | grep zengarden
```

Expected output:
```
compositeingresshosts.networking.zengarden.space   2024-10-31T...
partialingresses.networking.zengarden.space        2024-10-31T...
```

### View operator logs

```bash
# Shell-operator logs
kubectl logs -n ingress-nginx partial-ingress-operator-0 -c operator

# Handler service logs
kubectl logs -n ingress-nginx partial-ingress-operator-0 -c handler-service
```

## Testing

### Deploy example

```bash
kubectl apply -f partial-ingress-operator/examples/complete-example.yaml
```

### Check resources

```bash
# List PartialIngresses
kubectl get partialingresses --all-namespaces

# List CompositeIngressHosts
kubectl get compositeingresshosts --all-namespaces

# List generated Ingresses
kubectl get ingress --all-namespaces | grep -E "(retroboard|replicated)"
```

### Check status

```bash
kubectl describe partialingress retroboard -n ci-feat-oauth-retroboard
```

Expected status:
```yaml
Status:
  Generated Ingress:  retroboard
  Last Updated:       2024-10-31T12:00:00Z
  Replicated Ingresses:
    Name:           retroboard-api-6c3f8a9b
    Namespace:      dev-retroboard-api
    Source Ingress: dev-retroboard-api/retroboard-api
```

## Troubleshooting

### Operator pod not starting

Check events:
```bash
kubectl describe pod -n ingress-nginx partial-ingress-operator-0
```

Common issues:
- PVC not bound (check storage class)
- ServiceAccount permissions (check RBAC)
- Image pull issues

### CRDs not working

Verify CRDs are installed:
```bash
kubectl get crd partialingresses.networking.zengarden.space -o yaml
kubectl get crd compositeingresshosts.networking.zengarden.space -o yaml
```

### Ingress not being replicated

1. Check operator logs:
   ```bash
   kubectl logs -n ingress-nginx partial-ingress-operator-0 -c handler-service -f
   ```

2. Verify CompositeIngressHost matches:
   ```bash
   kubectl describe compositeingresshost -n <namespace> <name>
   ```

3. Check base Ingresses exist:
   ```bash
   kubectl get ingress --all-namespaces | grep <baseHost>
   ```

4. Verify hostname matches pattern:
   ```bash
   # Pattern: "app-*.domain.com"
   # Hostname: "app-pr-123.domain.com" ✓
   # Hostname: "other-app.domain.com" ✗
   ```

### Path conflicts

If paths are not being overridden correctly:
- Check path matching logic in operator logs
- Ensure exact path match (e.g., `/api` vs `/api/`)
- Path type matters: `Prefix` vs `Exact`

## Upgrading

### Upgrade operator

```bash
cd /Users/oleksiyp/dev/homelab/platform/helmfile/partial-ingress
helmfile sync
```

The StatefulSet will perform a rolling update automatically.

### Upgrade CRDs

CRDs are not automatically upgraded by Helm. To upgrade CRDs:

```bash
kubectl apply -f partial-ingress-operator/crds/
```

Then upgrade the operator:
```bash
helmfile sync
```

## Uninstalling

### Via Helmfile

```bash
helmfile destroy
```

### Manual

```bash
# Delete operator
helm uninstall partial-ingress-operator -n ingress-nginx

# Delete CRDs (WARNING: This deletes all PartialIngress and CompositeIngressHost resources!)
kubectl delete crd partialingresses.networking.zengarden.space
kubectl delete crd compositeingresshosts.networking.zengarden.space
```

## Production Considerations

1. **Resource Limits**: Adjust resource requests/limits in values.yaml based on cluster size
2. **Storage Class**: Configure appropriate storage class for PVC
3. **Monitoring**: Add Prometheus metrics and alerts
4. **High Availability**: Currently single replica. Consider adding HA support for production
5. **Backup**: Backup PartialIngress and CompositeIngressHost resources regularly

## References

- [Design Document](../../../../../designs/partial-ingress.md)
- [README](README.md)
- [Example Manifests](examples/)
