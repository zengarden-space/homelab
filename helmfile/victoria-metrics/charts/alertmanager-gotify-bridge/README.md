# Alertmanager Gotify Bridge Helm Chart

This Helm chart deploys the [alertmanager-gotify-bridge](https://github.com/druggeri/alertmanager_gotify_bridge) to send Alertmanager notifications to Gotify.

## Custom Templates

The chart supports custom Go templates for formatting alert titles and messages. This allows you to customize how alerts are presented in Gotify notifications.

### Enabling Custom Templates

To enable custom templates, set `templates.enabled: true` and provide template files in the `templates.files` section of your values:

```yaml
templates:
  enabled: true
  files:
    "title=mytoken.gotmpl": |
      {{ .Labels.alertname }} - {{ .Annotations.summary }}
    "mytoken.gotmpl": |
      **Alert:** {{ .Labels.alertname }}
      **Status:** {{ .Status }}
      **Description:** {{ .Annotations.description }}
      {{ if .Labels.instance }}**Instance:** {{ .Labels.instance }}{{ end }}
```

### Template Naming Convention

Templates follow a specific naming pattern:
- **Title templates**: `title=<token>.<extension>` - Used for notification titles
- **Message templates**: `<token>.<extension>` - Used for notification message body

The `<token>` corresponds to the Gotify application token. If you're using a specific token in your Alertmanager webhook configuration, name your templates accordingly.

### Supported File Extensions

- `.gohtml` - Go HTML templates
- `.gotmpl` - Go templates  
- `.tmpl` - Template files

### Template Data Structure

Templates receive an `Alert` object with the following structure:

```go
type Alert struct {
    Annotations  map[string]string  // Alert annotations (summary, description, etc.)
    Status       string            // "firing" or "resolved"
    Labels       map[string]string  // Alert labels (alertname, instance, etc.)
    GeneratorURL string            // URL to the source that generated the alert
    StartsAt     string            // When the alert started
    ValueString  string            // Alert value
    ExternalURL  string            // External URL
}
```

### Available Template Functions

The bridge includes Prometheus template functions:

- `first` - Get first element from a slice
- `reReplaceAll` - Regex replace all occurrences  
- `safeHtml` - Mark string as safe HTML
- `match` - Regex match
- `title` - Title case
- `toUpper` - Convert to uppercase
- `toLower` - Convert to lowercase
- `graphLink` - Generate Prometheus graph link
- `tableLink` - Generate Prometheus table link
- `stripPort` - Remove port from host:port string
- `humanize` - Human readable numbers
- `humanizePercentage` - Human readable percentages
- `humanizeDuration` - Human readable durations
- `humanizeTimestamp` - Human readable timestamps

### Example Templates

#### Simple Alert Title
```gotmpl
{{ .Labels.alertname }}{{ if .Labels.instance }} on {{ .Labels.instance }}{{ end }}
```

#### Markdown Message with Status
```gotmpl
**{{ if eq .Status "firing" }}🔥 FIRING{{ else }}✅ RESOLVED{{ end }}**

**Alert:** {{ .Labels.alertname }}
{{ if .Annotations.summary }}**Summary:** {{ .Annotations.summary }}{{ end }}
{{ if .Annotations.description }}**Description:** {{ .Annotations.description }}{{ end }}
{{ if .Labels.instance }}**Instance:** {{ .Labels.instance }}{{ end }}
{{ if .Labels.job }}**Job:** {{ .Labels.job }}{{ end }}

**Started:** {{ .StartsAt }}
{{ if .GeneratorURL }}[View in Prometheus]({{ .GeneratorURL }}){{ end }}
```

#### Conditional Formatting
```gotmpl
{{ $severity := .Labels.severity }}
{{ if eq $severity "critical" }}🚨 CRITICAL{{ else if eq $severity "warning" }}⚠️ WARNING{{ else }}ℹ️ INFO{{ end }}

{{ .Annotations.summary }}
{{ if .Annotations.description }}
{{ .Annotations.description }}
{{ end }}
```

### Token-based Template Selection

To use templates with specific Gotify tokens, you can pass the token in the webhook URL:

```yaml
# In Alertmanager configuration
webhook_configs:
  - url: http://alertmanager-gotify-bridge/gotify_webhook?token=myspecialtoken
```

Then create templates named:
- `title=myspecialtoken.gotmpl` for titles
- `myspecialtoken.gotmpl` for messages

### Default Fallback

If custom templates are not found or fail to execute, the bridge falls back to using the configured annotations:
- Title: Uses the annotation specified by `titleAnnotation` (default: "summary")
- Message: Uses the annotation specified by `messageAnnotation` (default: "description")

### Configuration Example

```yaml
# values.yaml
templates:
  enabled: true
  files:
    # Production alerts with token "prod"
    "title=prod.gotmpl": |
      {{ if eq .Status "firing" }}🔥{{ else }}✅{{ end }} {{ .Labels.alertname }}
    
    "prod.gotmpl": |
      **{{ .Labels.alertname }}** is {{ .Status }}
      
      {{ if .Annotations.summary }}{{ .Annotations.summary }}{{ end }}
      {{ if .Annotations.description }}
      
      {{ .Annotations.description }}{{ end }}
      
      **Instance:** {{ .Labels.instance | default "N/A" }}
      **Severity:** {{ .Labels.severity | default "unknown" }}
    
    # Development alerts with token "dev"  
    "title=dev.gotmpl": |
      [DEV] {{ .Labels.alertname }}
    
    "dev.gotmpl": |
      Development alert: {{ .Labels.alertname }}
      Status: {{ .Status }}
      {{ if .Annotations.description }}{{ .Annotations.description }}{{ end }}

config:
  gotifyToken: "your-default-token"
  # Other configuration...
```

This allows for different formatting based on the environment or alert type while maintaining flexibility in your alerting setup.
