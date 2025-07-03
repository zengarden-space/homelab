# Test Templates for Alertmanager Gotify Bridge

This directory contains example templates for testing the custom template functionality.

## Basic Test Templates

### title=test.gotmpl
```gotmpl
🧪 TEST: {{ .Labels.alertname }}
```

### test.gotmpl  
```gotmpl
**Test Alert Notification**

**Alert Name:** {{ .Labels.alertname }}
**Status:** {{ .Status }}
**Timestamp:** {{ .StartsAt }}

{{ if .Annotations.summary }}**Summary:** {{ .Annotations.summary }}{{ end }}
{{ if .Annotations.description }}**Description:** {{ .Annotations.description }}{{ end }}

{{ if .Labels.instance }}**Instance:** {{ .Labels.instance }}{{ end }}
{{ if .Labels.job }}**Job:** {{ .Labels.job }}{{ end }}
{{ if .Labels.severity }}**Severity:** {{ .Labels.severity }}{{ end }}

---
This message was generated using custom templates!
```

## Usage

1. Add these templates to your values.yaml:

```yaml
templates:
  enabled: true
  files:
    "title=test.gotmpl": |
      🧪 TEST: {{ .Labels.alertname }}
    "test.gotmpl": |
      **Test Alert Notification**
      
      **Alert Name:** {{ .Labels.alertname }}
      **Status:** {{ .Status }}
      **Timestamp:** {{ .StartsAt }}
      
      {{ if .Annotations.summary }}**Summary:** {{ .Annotations.summary }}{{ end }}
      {{ if .Annotations.description }}**Description:** {{ .Annotations.description }}{{ end }}
      
      {{ if .Labels.instance }}**Instance:** {{ .Labels.instance }}{{ end }}
      {{ if .Labels.job }}**Job:** {{ .Labels.job }}{{ end }}
      {{ if .Labels.severity }}**Severity:** {{ .Labels.severity }}{{ end }}
      
      ---
      This message was generated using custom templates!
```

2. Configure your Alertmanager to use the test token:

```yaml
webhook_configs:
  - url: http://alertmanager-gotify-bridge/gotify_webhook?token=test
```

3. Deploy and test with a sample alert!
