#!/bin/bash

set -eo pipefail

# Define hook configuration
if [[ "${1:-}" == "--config" ]]; then
  cat <<EOF
configVersion: v1
kubernetes:
- apiVersion: monitoring.zengarden.space/v1
  kind: GrafanaAlertRule
  executeHookOnEvent: ["Added", "Modified", "Deleted"]
  executeHookOnSynchronization: true
- apiVersion: monitoring.zengarden.space/v1
  kind: GrafanaNotificationPolicy
  executeHookOnEvent: ["Added", "Modified", "Deleted"]
  executeHookOnSynchronization: true
- apiVersion: monitoring.zengarden.space/v1
  kind: GrafanaMuteTiming
  executeHookOnEvent: ["Added", "Modified", "Deleted"]
  executeHookOnSynchronization: true
- apiVersion: monitoring.zengarden.space/v1
  kind: GrafanaNotificationTemplate
  executeHookOnEvent: ["Added", "Modified", "Deleted"]
  executeHookOnSynchronization: true
EOF
  exit 0
fi

# Main execution
TIMESTAMP=$(date +%s)
REQUEST_FILE="/shared/request-${TIMESTAMP}.json"
RESPONSE_FILE="/shared/response-${TIMESTAMP}.txt"

# Write binding context to shared volume
echo "$BINDING_CONTEXT" > "$REQUEST_FILE"

# Wait for handler service to process (max 60 seconds)
TIMEOUT=60
ELAPSED=0

while [[ ! -f "$RESPONSE_FILE" ]] && [[ $ELAPSED -lt $TIMEOUT ]]; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if [[ -f "$RESPONSE_FILE" ]]; then
  RESPONSE=$(cat "$RESPONSE_FILE")
  echo "Handler response: $RESPONSE"
  rm -f "$RESPONSE_FILE"

  # Check for errors
  if echo "$RESPONSE" | grep -q "^ERROR:"; then
    echo "Handler reported error: $RESPONSE" >&2
    exit 1
  fi
else
  echo "Handler timeout after ${TIMEOUT} seconds" >&2
  rm -f "$REQUEST_FILE"
  exit 1
fi
