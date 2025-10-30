#!/usr/bin/env bash

# This hook syncs CNPG Database resources to Metabase
# It watches for Database resources and creates/updates corresponding connections in Metabase

set -euo pipefail

# Configuration binding for shell-operator
if [[ "${1:-}" == "--config" ]]; then
  cat <<EOF
configVersion: v1
kubernetes:
  - apiVersion: postgresql.cnpg.io/v1
    kind: Database
    executeHookOnEvent: ["Added", "Modified"]
    executeHookOnSynchronization: true
    namespace:
      nameSelector:
        matchNames: []
    jqFilter: |
      {
        "namespace": .metadata.namespace,
        "name": .metadata.name,
        "clusterName": .spec.cluster.name,
        "dbName": .spec.name,
        "owner": .spec.owner
      }
schedule:
  - name: "periodic-sync"
    crontab: "*/5 * * * *"
    allowFailure: true
EOF
  exit 0
fi

# Load environment variables
METABASE_URL="${METABASE_URL:-http://metabase.metabase.svc.cluster.local}"
METABASE_ADMIN_EMAIL="${METABASE_ADMIN_EMAIL}"
METABASE_ADMIN_PASSWORD="${METABASE_ADMIN_PASSWORD}"

# Temporary directory for session
SESSION_FILE="/tmp/metabase-session"

# Logging helper
log() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] $*" >&2
}

# Authenticate to Metabase and get session token
metabase_login() {
  log "Authenticating to Metabase..."

  local response
  response=$(curl -s -X POST "${METABASE_URL}/api/session" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${METABASE_ADMIN_EMAIL}\",\"password\":\"${METABASE_ADMIN_PASSWORD}\"}")

  local session_id
  session_id=$(echo "$response" | jq -r '.id // empty')

  if [[ -z "$session_id" ]]; then
    log "ERROR: Failed to authenticate to Metabase"
    log "Response: $response"
    return 1
  fi

  echo "$session_id" > "$SESSION_FILE"
  log "Successfully authenticated to Metabase"
  return 0
}

# Get Metabase session token
get_session() {
  if [[ -f "$SESSION_FILE" ]]; then
    cat "$SESSION_FILE"
  else
    metabase_login
    cat "$SESSION_FILE"
  fi
}

# Get all databases from Metabase
get_metabase_databases() {
  local session
  session=$(get_session)

  local response
  response=$(curl -s -X GET "${METABASE_URL}/api/database" \
    -H "X-Metabase-Session: ${session}")

  # Check if we got unauthorized (session expired)
  if echo "$response" | jq -e '.message == "Unauthenticated"' >/dev/null 2>&1; then
    log "Session expired, re-authenticating..."
    metabase_login
    session=$(cat "$SESSION_FILE")
    response=$(curl -s -X GET "${METABASE_URL}/api/database" \
      -H "X-Metabase-Session: ${session}")
  fi

  echo "$response"
}

# Check if database exists in Metabase by name
database_exists() {
  local db_name="$1"
  local databases
  databases=$(get_metabase_databases)

  echo "$databases" | jq -e --arg name "$db_name" '.data[]? | select(.name == $name)' >/dev/null 2>&1
}

# Get database ID from Metabase by name
get_database_id() {
  local db_name="$1"
  local databases
  databases=$(get_metabase_databases)

  echo "$databases" | jq -r --arg name "$db_name" '.data[]? | select(.name == $name) | .id'
}

# Get CNPG cluster connection details
get_cluster_details() {
  local namespace="$1"
  local cluster_name="$2"

  kubectl get cluster.postgresql.cnpg.io "$cluster_name" -n "$namespace" -o json
}

# Get credentials for a role from secret
get_role_credentials() {
  local namespace="$1"
  local secret_name="$2"

  local username
  local password

  username=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
  password=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

  if [[ -z "$username" || -z "$password" ]]; then
    return 1
  fi

  jq -n --arg user "$username" --arg pass "$password" '{username: $user, password: $pass}'
}

# Create database in Metabase
create_metabase_database() {
  local db_name="$1"
  local host="$2"
  local port="$3"
  local database="$4"
  local username="$5"
  local password="$6"
  local namespace="$7"

  local session
  session=$(get_session)

  log "Creating database '$db_name' in Metabase..."

  local payload
  payload=$(jq -n \
    --arg name "$db_name" \
    --arg engine "postgres" \
    --arg host "$host" \
    --arg port "$port" \
    --arg dbname "$database" \
    --arg user "$username" \
    --arg pass "$password" \
    --arg ns "$namespace" \
    '{
      name: $name,
      engine: $engine,
      details: {
        host: $host,
        port: ($port | tonumber),
        dbname: $dbname,
        user: $user,
        password: $pass,
        ssl: true,
        "ssl-mode": "require",
        "tunnel-enabled": false
      },
      is_full_sync: true,
      is_on_demand: false,
      schedules: {
        metadata_sync: {
          schedule_day: null,
          schedule_frame: null,
          schedule_hour: 0,
          schedule_type: "hourly"
        },
        cache_field_values: {
          schedule_day: null,
          schedule_frame: null,
          schedule_hour: 0,
          schedule_type: "hourly"
        }
      },
      auto_run_queries: true,
      refingerprint: false
    }')

  local response
  response=$(curl -s -X POST "${METABASE_URL}/api/database" \
    -H "Content-Type: application/json" \
    -H "X-Metabase-Session: ${session}" \
    -d "$payload")

  # Check for auth errors
  if echo "$response" | jq -e '.message == "Unauthenticated"' >/dev/null 2>&1; then
    log "Session expired, re-authenticating..."
    metabase_login
    session=$(cat "$SESSION_FILE")
    response=$(curl -s -X POST "${METABASE_URL}/api/database" \
      -H "Content-Type: application/json" \
      -H "X-Metabase-Session: ${session}" \
      -d "$payload")
  fi

  local db_id
  db_id=$(echo "$response" | jq -r '.id // empty')

  if [[ -n "$db_id" ]]; then
    log "Successfully created database '$db_name' with ID: $db_id"

    # Trigger schema sync
    log "Triggering schema sync for database ID: $db_id"
    curl -s -X POST "${METABASE_URL}/api/database/${db_id}/sync_schema" \
      -H "X-Metabase-Session: ${session}" >/dev/null

    # Trigger field values scan
    log "Triggering field values rescan for database ID: $db_id"
    curl -s -X POST "${METABASE_URL}/api/database/${db_id}/rescan_values" \
      -H "X-Metabase-Session: ${session}" >/dev/null

    return 0
  else
    log "ERROR: Failed to create database '$db_name'"
    log "Response: $response"
    return 1
  fi
}

# Update database in Metabase
update_metabase_database() {
  local db_id="$1"
  local db_name="$2"
  local host="$3"
  local port="$4"
  local database="$5"
  local username="$6"
  local password="$7"

  local session
  session=$(get_session)

  log "Updating database '$db_name' (ID: $db_id) in Metabase..."

  local payload
  payload=$(jq -n \
    --arg name "$db_name" \
    --arg engine "postgres" \
    --arg host "$host" \
    --arg port "$port" \
    --arg dbname "$database" \
    --arg user "$username" \
    --arg pass "$password" \
    '{
      name: $name,
      engine: $engine,
      details: {
        host: $host,
        port: ($port | tonumber),
        dbname: $dbname,
        user: $user,
        password: $pass,
        ssl: true,
        "ssl-mode": "require",
        "tunnel-enabled": false
      },
      is_full_sync: true,
      is_on_demand: false,
      auto_run_queries: true
    }')

  local response
  response=$(curl -s -X PUT "${METABASE_URL}/api/database/${db_id}" \
    -H "Content-Type: application/json" \
    -H "X-Metabase-Session: ${session}" \
    -d "$payload")

  if echo "$response" | jq -e '.message == "Unauthenticated"' >/dev/null 2>&1; then
    log "Session expired, re-authenticating..."
    metabase_login
    session=$(cat "$SESSION_FILE")
    response=$(curl -s -X PUT "${METABASE_URL}/api/database/${db_id}" \
      -H "Content-Type: application/json" \
      -H "X-Metabase-Session: ${session}" \
      -d "$payload")
  fi

  log "Updated database '$db_name'"

  # Trigger schema sync
  log "Triggering schema sync for database ID: $db_id"
  curl -s -X POST "${METABASE_URL}/api/database/${db_id}/sync_schema" \
    -H "X-Metabase-Session: ${session}" >/dev/null

  # Trigger field values scan
  log "Triggering field values rescan for database ID: $db_id"
  curl -s -X POST "${METABASE_URL}/api/database/${db_id}/rescan_values" \
    -H "X-Metabase-Session: ${session}" >/dev/null

  return 0
}

# Sync a single CNPG database to Metabase
sync_database() {
  local namespace="$1"
  local db_resource_name="$2"
  local cluster_name="$3"
  local db_name="$4"
  local owner="$5"

  log "Processing database: $namespace/$db_resource_name (cluster: $cluster_name, db: $db_name, owner: $owner)"

  # Get cluster details
  local cluster
  cluster=$(get_cluster_details "$namespace" "$cluster_name")

  if [[ -z "$cluster" ]]; then
    log "ERROR: Cluster $cluster_name not found in namespace $namespace"
    return 1
  fi

  # Extract connection details
  local write_service
  write_service=$(echo "$cluster" | jq -r '.status.writeService')
  local host="${write_service}.${namespace}.svc.cluster.local"
  local port="5432"

  log "Cluster connection: $host:$port"

  # Get credentials for the owner role
  local creds
  creds=$(get_role_credentials "$namespace" "$owner")

  if [[ -z "$creds" ]]; then
    log "ERROR: Could not find credentials for role $owner in namespace $namespace"
    return 1
  fi

  local username
  local password
  username=$(echo "$creds" | jq -r '.username')
  password=$(echo "$creds" | jq -r '.password')

  # Create a unique name for Metabase
  local metabase_db_name="${namespace}/${db_name}"

  # Check if database exists in Metabase
  if database_exists "$metabase_db_name"; then
    log "Database '$metabase_db_name' already exists in Metabase"
    local db_id
    db_id=$(get_database_id "$metabase_db_name")
    if [[ -n "$db_id" ]]; then
      update_metabase_database "$db_id" "$metabase_db_name" "$host" "$port" "$db_name" "$username" "$password"
    fi
  else
    create_metabase_database "$metabase_db_name" "$host" "$port" "$db_name" "$username" "$password" "$namespace"
  fi
}

# Process events from shell-operator
process_events() {
  local binding_context
  binding_context=$(cat "$BINDING_CONTEXT_PATH")

  log "Processing events..."
  log "DEBUG: Binding context: $binding_context"

  # Handle scheduled reconciliation
  if echo "$binding_context" | jq -e '.[0].type == "Schedule"' >/dev/null 2>&1; then
    log "Running scheduled reconciliation..."

    # Get all CNPG databases
    local databases
    databases=$(kubectl get databases.postgresql.cnpg.io -A -o json)

    log "DEBUG: Found databases: $(echo "$databases" | jq -c '.items | length') items"

    echo "$databases" | jq -c '.items[]' | while read -r db; do
      local namespace
      local name
      local cluster_name
      local db_name
      local owner

      namespace=$(echo "$db" | jq -r '.metadata.namespace')
      name=$(echo "$db" | jq -r '.metadata.name')
      cluster_name=$(echo "$db" | jq -r '.spec.cluster.name')
      db_name=$(echo "$db" | jq -r '.spec.name')
      owner=$(echo "$db" | jq -r '.spec.owner')

      sync_database "$namespace" "$name" "$cluster_name" "$db_name" "$owner" || true
    done

    log "Scheduled reconciliation completed"
    return 0
  fi

  # Handle resource events
  echo "$binding_context" | jq -c '.[]' | while read -r event; do
    local event_type
    local binding
    event_type=$(echo "$event" | jq -r '.type // "Synchronization"')
    binding=$(echo "$event" | jq -r '.binding // "unknown"')

    log "Event type: $event_type, Binding: $binding"

    # Handle Synchronization event (initial sync)
    if [[ "$event_type" == "Synchronization" ]]; then
      log "Running initial synchronization..."

      # During synchronization, each object in the objects array has a filterResult field
      local objects
      objects=$(echo "$event" | jq -c '.objects // []')

      log "DEBUG: objects type: $(echo "$objects" | jq -r 'type')"
      log "DEBUG: objects length: $(echo "$objects" | jq -r 'length')"

      if [[ "$objects" != "[]" && "$objects" != "null" ]]; then
        echo "$objects" | jq -c '.[]' | while read -r obj; do
          # Extract the filterResult from each object
          local filtered_obj
          filtered_obj=$(echo "$obj" | jq -c '.filterResult // empty')

          if [[ -z "$filtered_obj" || "$filtered_obj" == "null" ]]; then
            log "DEBUG: No filterResult in object, skipping"
            continue
          fi

          local namespace
          local name
          local cluster_name
          local db_name
          local owner

          log "DEBUG: Processing filtered object: $filtered_obj"

          namespace=$(echo "$filtered_obj" | jq -r '.namespace')
          name=$(echo "$filtered_obj" | jq -r '.name')
          cluster_name=$(echo "$filtered_obj" | jq -r '.clusterName')
          db_name=$(echo "$filtered_obj" | jq -r '.dbName')
          owner=$(echo "$filtered_obj" | jq -r '.owner')

          sync_database "$namespace" "$name" "$cluster_name" "$db_name" "$owner" || true
        done
      else
        log "No databases found during synchronization"
      fi
      continue
    fi

    # Handle Added/Modified events with filterResult
    local filtered_object
    filtered_object=$(echo "$event" | jq -r '.filterResult // empty')

    if [[ -z "$filtered_object" || "$filtered_object" == "null" ]]; then
      log "No filterResult in event, skipping"
      continue
    fi

    local namespace
    local name
    local cluster_name
    local db_name
    local owner

    namespace=$(echo "$filtered_object" | jq -r '.namespace')
    name=$(echo "$filtered_object" | jq -r '.name')
    cluster_name=$(echo "$filtered_object" | jq -r '.clusterName')
    db_name=$(echo "$filtered_object" | jq -r '.dbName')
    owner=$(echo "$filtered_object" | jq -r '.owner')

    sync_database "$namespace" "$name" "$cluster_name" "$db_name" "$owner" || true
  done

  log "Event processing completed"
}

# Main execution
main() {
  log "=== Metabase CNPG Operator Hook Starting ==="

  # Verify required tools
  if ! command -v kubectl &> /dev/null; then
    log "ERROR: kubectl not found"
    exit 1
  fi

  if ! command -v jq &> /dev/null; then
    log "ERROR: jq not found"
    exit 1
  fi

  if ! command -v curl &> /dev/null; then
    log "ERROR: curl not found"
    exit 1
  fi

  # Verify Metabase credentials
  if [[ -z "${METABASE_ADMIN_EMAIL:-}" || -z "${METABASE_ADMIN_PASSWORD:-}" ]]; then
    log "ERROR: METABASE_ADMIN_EMAIL and METABASE_ADMIN_PASSWORD must be set"
    exit 1
  fi

  # Process events
  process_events

  log "=== Metabase CNPG Operator Hook Completed ==="
}

# Run main function
main
