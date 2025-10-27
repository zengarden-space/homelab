# Alertmanager to Gotify Bridge (Node.js)

A lightweight Node.js application that bridges Prometheus AlertManager notifications to Gotify push ### Example Input (AlertManager Webhook v4)
```js### Title Format
```
**<N> alerts** <date_time>
```

- **Alert Count**: Shows the number of alerts in the notification
- **Date/Time**: Current timestamp in GB format with UTC timezone


**Example titles:**
- `**1 alerts** 3 Jul 2025 20:15 UTC` - Single alert
- `**5 alerts** 3 Jul 2025 20:15 UTC` - Multiple alerts": "4",
  "groupKey": "{}:{alertname=\"HighCPUUsage\"}",
  "status": "firing",
  "receiver": "gotify-notifications",
  "groupLabels": {
    "alertname": "HighCPUUsage"
  },
  "commonLabels": {
    "alertname": "HighCPUUsage",
    "severity": "warning",
    "service": "web"
  },
  "commonAnnotations": {
    "summary": "High CPU usage detected",
    "description": "CPU usage is above 90% for more than 5 minutes"
  },
  "externalURL": "http://alertmanager:9093",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "HighCPUUsage",
        "instance": "server1:9100",
        "severity": "warning",
        "service": "web"
      },
      "annotations": {
        "summary": "High CPU usage detected",
        "description": "CPU usage is above 90% for more than 5 minutes"
      },
      "startsAt": "2025-07-03T10:30:00.000Z",
      "endsAt": "0001-01-01T00:00:00Z",
      "generatorURL": "http://prometheus:9090/graph?g0.expr=...",
      "fingerprint": "abcdef123456"
    }
  ]
}
```

### Example Output (Gotify Message)
```json
{
  "title": "**1 alerts** 3 Jul 2025 20:15 UTC",
  "message": "⚠️ HighCPUUsage server1:9100\n\n- Summary: High CPU usage detected\n- Description: CPU usage is above 90% for more than 5 minutes\n- [Go to Alertmanager](http://alertmanager:9093)\n\n---\n**🔥 ⚠️ HighCPUUsage server1:9100**\n- [Go to Prometheus](http://prometheus:9090/graph?g0.expr=...)\n\n**Labels:**\n- 🏷️ alertname = HighCPUUsage\n- 🏷️ instance = server1:9100\n- 🏷️ service = web\n- 🏷️ severity = warning\n\n**Annotations:**\n- ✍️ description = CPU usage is above 90% for more than 5 minutes\n- ✍️ summary = High CPU usage detected\n\n**Timestamps:**\n- ⏰ Started: 4 hours and 30 minutes ago\n- 🔍 Fingerprint: abcdef123456",
  "priority": 7,
  "extras": {
    "client::display": {
      "contentType": "text/markdown"
    }
  }
}
```Features

- 🚀 **Lightweight**: Built with Node.js and minimal dependencies
- 🔄 **Reliable**: Handles multiple alerts concurrently with proper error handling
- 📊 **Observable**: Built-in health checks and configurable probes
- 🛡️ **Secure**: Runs as non-root user with minimal privileges
- 🐳 **Cloud Native**: Kubernetes-ready with Helm chart - no custom Docker image required
- 🏗️ **ARM64 Compatible**: Uses standard Node.js images, fully multi-architecture compatible
- ⚡ **Zero Build**: Application code is mounted directly from ConfigMap

## Architecture

This chart uses a modern, build-free approach:

1. **ConfigMap**: Contains the Node.js application code (`app.js`) and `package.json`
2. **InitContainer**: Runs `npm install` to fetch dependencies into an EmptyDir volume
3. **Main Container**: Starts the application using the standard Node.js image
4. **No Custom Image**: Uses only the official `node:18-alpine` image

## Quick Start

### Using Helm

```bash
# Install the chart
helm install alertmanager-gotify-bridge ./charts/alertmanager-gotify-nodejs \
  --set config.gotifyEndpoint="http://gotify:8080/message" \
  --set config.gotifyToken="your-gotify-token"
```

### Customizing the Application

Since the application code is stored in a ConfigMap, you can easily modify it by updating the chart templates without building custom Docker images.

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GOTIFY_MESSAGE_ENDPOINT` | Gotify message endpoint URL | `http://gotify:8080/message` |
| `GOTIFY_TOKEN` | Gotify application token | `` |
| `LISTEN_PORT` | Port to listen on | `8435` |
| `LISTEN_ADDR` | Address to bind to | `0.0.0.0` |
| `DEFAULT_PRIORITY` | Default notification priority | `5` |
| `SEND_RESOLVED` | Whether to send resolved alerts | `false` |

### Helm Values

```yaml
# Image configuration (uses standard Node.js image)
image:
  repository: node
  tag: "18-alpine"
  pullPolicy: IfNotPresent

# Application configuration
config:
  gotifyEndpoint: "http://gotify:8080/message"
  gotifyToken: "your-gotify-token"
  listenPort: 8435
  listenAddr: "0.0.0.0"
  defaultPriority: 5
  sendResolved: false

# Resource limits
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

# Health check probes
probes:
  liveness:
    enabled: true
    initialDelaySeconds: 30
  readiness:
    enabled: true
    initialDelaySeconds: 5
```

## AlertManager Configuration

Configure AlertManager to send webhooks to the bridge:

```yaml
route:
  receiver: 'gotify-notifications'

receivers:
  - name: 'gotify-notifications'
    webhook_configs:
      - url: 'http://alertmanager-gotify-nodejs:8435/'
        send_resolved: false  # Set to true if you want resolved alerts
```

## Alert Processing

The bridge processes AlertManager webhooks and converts them to Gotify notifications using sophisticated formatting logic inspired by the official Gotify AlertManager plugin:

### Features

- **Markdown Support**: Messages are formatted as Markdown for rich display
- **Smart Emoji Mapping**: Status and severity are mapped to appropriate emojis
- **Priority Calculation**: Automatic priority assignment based on alert severity
- **Grouped Alerts**: Processes AlertManager grouped alerts efficiently
- **HTML Escaping**: Secure handling of alert content
- **Version Compatibility**: Supports AlertManager webhook version 4

### Emoji Mapping

| Status/Severity | Emoji | Priority |
|----------------|-------|----------|
| Firing | 🔥 | - |
| Resolved | 🙂 (resolved) | - |
| Info | 💡 | 0 |
| Warning | ⚠️ | 7 |
| Critical | 🆘 🆘 🆘 | 10 |

### Message Format

The bridge creates rich markdown messages with:

- **Title**: Status emoji + severity emoji + alert name/instance
- **Summary/Description**: From alert annotations
- **Links**: To AlertManager and Prometheus
- **Alert Details**: Instance, timestamps, fingerprint
- **Labels/Annotations**: Both common and alert-specific

## Message Formatting

The bridge implements advanced message formatting with the following features:

### Title Format
```
{status_emoji} {grouped_severities} ({date_time})
```

- **Status Emoji**: 🔥 for firing alerts, 🙂 (resolved) for resolved alerts
- **Grouped Severities**: Shows individual severity emojis for each unique `alertname+severity` combination
  - Single alert: `🆘` (critical), `⚠️` (warning), `💡` (info)
  - Multiple alerts of same type: `2×🆘` (2 critical alerts), `3×⚠️` (3 warning alerts)
- **Date/Time**: Current timestamp in GB format with GMT timezone


**Example titles:**
- `1 alerts 3 Jul 2025 20:15 UTC` - Single alert (new format)
- `2 alerts 3 Jul 2025 20:15 UTC` - Two alerts (new format)

### Message Format
1. **Alert List**: Quick overview of all alerts
   ```
   🆘 DatabaseDown production/postgres
   ⚠️ HighCPUUsage web-server-1:9100
   💡 SlowQuery default/api-service
   ```
   
2. **Common Information**: Shared annotations and Alertmanager link

3. **Detailed Sections**: Per-alert details with:
   - Labels and annotations
   - Relative timestamps ("2 hours and 15 minutes ago")
   - Prometheus generator links
   - Alert fingerprints

### Identifying Information Logic
The bridge intelligently extracts identifying information from alert labels:

1. **Kubernetes Pods**: `namespace/pod (container)`
2. **Kubernetes Services**: `namespace/service`
3. **Kubernetes Jobs**: `namespace/job`
4. **Infrastructure**: `instance`, `node`, `device`
5. **Fallback**: `job`, `hostname`, or "unknown"

## Priority Mapping

The bridge maps alert severity to Gotify priority:

| Severity | Priority | Description |
|----------|----------|-------------|
| `critical` | 10 | Highest priority |
| `warning` | 7 | Medium priority |
| Custom `priority` annotation | As specified | Custom priority |
| Default | 5 | Normal priority |

## Endpoints

- `GET /health` - Health check endpoint that returns JSON status
- `POST /` - AlertManager webhook endpoint

## Health Check

The health endpoint returns:

```json
{
  "status": "healthy",
  "timestamp": "2025-07-03T10:30:00.000Z",
  "service": "alertmanager-gotify-nodejs"
}
```

## Development

### Local Testing

You can test the chart locally by modifying the ConfigMap and redeploying:

```bash
# Update the chart and test
helm upgrade alertmanager-gotify-bridge ./charts/alertmanager-gotify-nodejs \
  --set config.gotifyEndpoint="http://gotify:8080/message" \
  --set config.gotifyToken="your-gotify-token"
```

### Testing the Webhook

Send a test webhook to the deployed service:

```bash
# Get the service URL (adjust for your setup)
kubectl port-forward service/alertmanager-gotify-nodejs 8435:80

# Send test alert
curl -X POST http://localhost:8435/ \
  -H "Content-Type: application/json" \
  -d '{
    "alerts": [{
      "status": "firing",
      "labels": {
        "alertname": "TestAlert",
        "severity": "warning",
        "instance": "test-server:9100"
      },
      "annotations": {
        "summary": "Test Alert",
        "description": "This is a test alert to verify the bridge is working"
      }
    }]
  }'
```

## Deployment Examples

### Helm Installation

```bash
# Basic installation
helm install my-bridge ./charts/alertmanager-gotify-nodejs \
  --set config.gotifyEndpoint="http://gotify:8080/message" \
  --set config.gotifyToken="your-gotify-token"

# With custom values
helm install my-bridge ./charts/alertmanager-gotify-nodejs \
  --values my-values.yaml
```

### Sample values.yaml

```yaml
# Custom configuration
config:
  gotifyEndpoint: "https://gotify.example.com/message"
  gotifyToken: "APP_TOKEN_FROM_GOTIFY"
  sendResolved: true
  defaultPriority: 7

# Resource adjustments for production
resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

# Enable ingress if needed
ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: alertmanager-bridge.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: alertmanager-bridge-tls
      hosts:
        - alertmanager-bridge.example.com
```

## Troubleshooting

### Common Issues

1. **Connection refused to Gotify**
   - Check `GOTIFY_MESSAGE_ENDPOINT` is correct
   - Verify network connectivity
   - Ensure Gotify is running

2. **Authentication errors**
   - Verify `GOTIFY_TOKEN` is correct
   - Check token permissions in Gotify

3. **No alerts received**
   - Verify AlertManager webhook URL
   - Check AlertManager routing rules
   - Review bridge logs

### Logs

The application provides structured logging:

```bash
# View Kubernetes pod logs
kubectl logs deployment/alertmanager-gotify-nodejs

# Follow logs in real-time
kubectl logs -f deployment/alertmanager-gotify-nodejs

# View logs from all replicas
kubectl logs -l app.kubernetes.io/name=alertmanager-gotify-nodejs
```

## Contributing

This chart is designed to be easily customizable. To modify the Node.js application:

1. Edit the `app.js` code in `templates/configmap.yaml`
2. Update dependencies in the `package.json` section if needed
3. Deploy the updated chart

The approach of using ConfigMaps makes it easy to iterate and customize without Docker builds.

## Security Considerations

- The application runs as a non-root user (UID 1000)
- No privileged capabilities required
- Minimal attack surface with few dependencies
- Supports network policies for traffic isolation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see LICENSE file for details.
