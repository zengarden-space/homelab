# Grafana Alert Operator

Kubernetes operator for managing Grafana alerting resources via Custom Resource Definitions (CRDs).

## Overview

This operator allows you to manage Grafana alerts, notification policies, mute timings, and notification templates as Kubernetes resources, enabling GitOps workflows for Grafana alerting configuration.

## Features

- **Declarative Configuration**: Define Grafana alerts as Kubernetes CRDs
- **GitOps Ready**: Store alerting configuration in Git alongside application code
- **Multi-Grafana Support**: Manage alerts across multiple Grafana instances
- **Status Tracking**: Monitor sync status via Kubernetes status subresources
- **Automatic Reconciliation**: Operator ensures Grafana state matches desired CRD state

## Supported Resources

| CRD | Description | Shortname |
|-----|-------------|-----------|
| `GrafanaAlertRule` | Alert rule definitions | `gar` |
| `GrafanaNotificationPolicy` | Alert routing policies | `gnp` |
| `GrafanaMuteTiming` | Scheduled alert suppression | `gmt` |
| `GrafanaNotificationTemplate` | Notification message templates | `gnt` |

## Prerequisites

1. **Kubernetes cluster** with CRD support
2. **Grafana instance** with Alerting API enabled
3. **Service account token** provisioned in Grafana (see Setup below)

## Installation

### 1. Deploy Operator

```bash
cd platform/helmfile/victoria-metrics
helmfile -f grafana-alert-operator/helmfile.yaml.gotmpl sync
```

### 2. Create Grafana Service Account Token

The operator requires a service account token to authenticate with Grafana. This should be provisioned by the Grafana chart during installation.

**Manual setup** (if not using Grafana chart job):

1. In Grafana UI: `Administration → Users and access → Service Accounts`
2. Create service account: `kubernetes-alert-operator`
3. Assign role: `Editor` or `Admin`
4. Generate token with no expiration
5. Store token in Kubernetes Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-operator-token
  namespace: monitoring
type: Opaque
stringData:
  token: "glsa_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  url: "http://grafana.monitoring.svc.cluster.local:3000"
  orgId: "1"
```

### 3. Verify Deployment

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana-alert-operator
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana-alert-operator -c handler-service
```

## Usage

### Creating an Alert Rule

```yaml
apiVersion: monitoring.zengarden.space/v1
kind: GrafanaAlertRule
metadata:
  name: high-cpu-alert
  namespace: dev-myapp
spec:
  grafanaRef:
    secretRef:
      name: grafana-operator-token
      namespace: monitoring

  folderUID: "app-alerts"
  ruleGroup: "Performance"

  title: "High CPU Usage"
  condition: "C"
  noDataState: "NoData"
  execErrState: "Alerting"
  for: "5m"

  annotations:
    summary: "CPU usage above 80% for {{ $labels.pod }}"
    description: "Pod {{ $labels.pod }} in {{ $labels.namespace }} has CPU usage at {{ $value }}%"
    runbook_url: "https://wiki.example.com/runbooks/high-cpu"

  labels:
    severity: "warning"
    team: "platform"

  data:
    - refId: "A"
      queryType: "prometheus"
      relativeTimeRange:
        from: 600
        to: 0
      datasourceUid: "prometheus-uid"
      model:
        expr: 'rate(container_cpu_usage_seconds_total{pod=~"myapp-.*"}[5m]) * 100'
        refId: "A"

    - refId: "C"
      queryType: "math"
      relativeTimeRange:
        from: 600
        to: 0
      model:
        expression: "$A > 80"
        refId: "C"
```

### Creating a Notification Policy

```yaml
apiVersion: monitoring.zengarden.space/v1
kind: GrafanaNotificationPolicy
metadata:
  name: team-routing
  namespace: dev-myapp
spec:
  grafanaRef:
    secretRef:
      name: grafana-operator-token
      namespace: monitoring

  receiver: "default-receiver"
  groupBy: ["alertname", "namespace"]
  groupWait: "30s"
  groupInterval: "5m"
  repeatInterval: "4h"

  matchers:
    - label: "team"
      match: "="
      value: "platform"

  routes:
    - receiver: "slack-critical"
      matchers:
        - label: "severity"
          match: "="
          value: "critical"
    - receiver: "pagerduty"
      matchers:
        - label: "severity"
          match: "="
          value: "critical"
      continue: true
```

### Creating a Mute Timing

```yaml
apiVersion: monitoring.zengarden.space/v1
kind: GrafanaMuteTiming
metadata:
  name: business-hours-only
  namespace: dev-myapp
spec:
  grafanaRef:
    secretRef:
      name: grafana-operator-token
      namespace: monitoring

  name: "outside-business-hours"
  timeIntervals:
    - weekdays: ["saturday", "sunday"]
    - times:
        - startTime: "00:00"
          endTime: "09:00"
      weekdays: ["monday", "tuesday", "wednesday", "thursday", "friday"]
    - times:
        - startTime: "17:00"
          endTime: "23:59"
      weekdays: ["monday", "tuesday", "wednesday", "thursday", "friday"]
```

### Creating a Notification Template

```yaml
apiVersion: monitoring.zengarden.space/v1
kind: GrafanaNotificationTemplate
metadata:
  name: slack-template
  namespace: dev-myapp
spec:
  grafanaRef:
    secretRef:
      name: grafana-operator-token
      namespace: monitoring

  name: "slack-alert"
  template: |
    {{ define "slack.title" }}
    [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .GroupLabels.alertname }}
    {{ end }}

    {{ define "slack.text" }}
    {{ range .Alerts }}
    *Alert:* {{ .Labels.alertname }}
    *Summary:* {{ .Annotations.summary }}
    *Description:* {{ .Annotations.description }}
    {{ end }}
    {{ end }}
```

## Checking Status

```bash
# List alert rules
kubectl get grafanaalertrules -A

# Check specific alert rule status
kubectl get grafanaalertrule high-cpu-alert -n dev-myapp -o yaml

# View sync status
kubectl get grafanaalertrule high-cpu-alert -n dev-myapp -o jsonpath='{.status.syncStatus}'
```

## Architecture

The operator consists of two containers:

1. **Shell-operator**: Watches Kubernetes resources and triggers reconciliation
2. **Python Service**: Communicates with Grafana API to sync resources

Communication between containers uses file-based IPC via shared volume (`/shared`).

## Security

- Runs as non-root user (UID 1000)
- Read-only root filesystem
- Drops all Linux capabilities
- Service account token stored securely in Kubernetes Secrets

## Troubleshooting

### Alert rule not syncing

```bash
# Check operator logs
kubectl logs -n monitoring deployment/grafana-alert-operator -c handler-service

# Check CRD status
kubectl describe grafanaalertrule <name> -n <namespace>
```

### Authentication errors

- Verify Grafana service account token is valid
- Check token has appropriate permissions (Editor or Admin role)
- Ensure Secret reference is correct in CRD spec

### Resource not found in Grafana

- Verify `folderUID` exists in Grafana
- Check datasource UIDs are correct
- Ensure Grafana URL is accessible from operator pod

## Development

### Testing locally

```bash
# Apply CRDs
kubectl apply -f grafana-alert-operator/crds/

# Deploy operator
helmfile -f grafana-alert-operator/helmfile.yaml.gotmpl sync

# Create test alert rule
kubectl apply -f grafana-alert-operator/examples/
```

### Updating operator

```bash
# Make changes to Python service or hook script
# Helm will automatically restart pods when ConfigMaps change

helmfile -f grafana-alert-operator/helmfile.yaml.gotmpl sync
```

## References

- [Grafana Alerting API Documentation](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/http-api-provisioning/)
- [Shell-operator Documentation](https://github.com/flant/shell-operator)
- [Kubernetes Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
