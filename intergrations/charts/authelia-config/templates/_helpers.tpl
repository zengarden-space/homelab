{{/*
Authelia users database content
*/}}
{{- define "authelia-config.users" -}}
users: {{ .Values.users | toYaml | nindent 2 }}
{{- end }}
