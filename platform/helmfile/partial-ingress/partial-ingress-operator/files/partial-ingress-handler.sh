#!/usr/bin/env bash

set -euo pipefail

# Shell-operator configuration for PartialIngress
if [[ "${1:-}" == "--config" ]]; then
  cat <<'HOOKEOF'
configVersion: v1
kubernetes:
  - apiVersion: networking.zengarden.space/v1
    kind: PartialIngress
    executeHookOnEvent: ["Added", "Modified", "Deleted"]
    executeHookOnSynchronization: true
  - apiVersion: networking.zengarden.space/v1
    kind: CompositeIngressHost
    executeHookOnEvent: ["Added", "Modified"]
    executeHookOnSynchronization: true
HOOKEOF
  exit 0
fi

# File-based IPC approach - write request, wait for response
SHARED_DIR="/shared"
REQUEST_ID=$(date +%s%N)
REQUEST_FILE="${SHARED_DIR}/request-${REQUEST_ID}.json"
RESPONSE_FILE="${SHARED_DIR}/response-${REQUEST_ID}.txt"

# Ensure binding context file exists and is non-empty
if [[ ! -s "$BINDING_CONTEXT_PATH" ]]; then
  echo "ERROR: binding context file missing or empty: $BINDING_CONTEXT_PATH" >&2
  exit 1
fi

# Write the binding context as the request
echo "Writing request to ${REQUEST_FILE}..."
cat "$BINDING_CONTEXT_PATH" > "$REQUEST_FILE"

# Wait for response file (with timeout)
echo "Waiting for handler service response..."
for i in {1..60}; do
  if [[ -f "$RESPONSE_FILE" ]]; then
    response=$(cat "$RESPONSE_FILE")

    # Clean up files
    rm -f "$REQUEST_FILE" "$RESPONSE_FILE"

    echo "Handler response: $response"

    # Check response status
    if [[ "$response" == "OK" ]]; then
      echo "✓ Successfully processed resource"
      exit 0
    else
      echo "ERROR: Handler failed: $response" >&2
      exit 1
    fi
  fi
  sleep 0.5
done

# Timeout - clean up request file
rm -f "$REQUEST_FILE"
echo "ERROR: Timeout waiting for handler service" >&2
exit 1
