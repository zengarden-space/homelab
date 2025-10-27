#!/bin/sh
set -e

echo "Waiting for Metabase to be ready..."
MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if curl -s -f "${METABASE_URL}/api/health" > /dev/null 2>&1; then
    echo "Metabase is healthy"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  echo "Waiting for Metabase... attempt $ATTEMPT/$MAX_ATTEMPTS"
  sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo "ERROR: Metabase did not become healthy in time"
  exit 1
fi

# Check if setup is already done
echo "Checking if Metabase is already set up..."
PROPERTIES=$(curl -s "${METABASE_URL}/api/session/properties")
SETUP_TOKEN=$(echo "$PROPERTIES" | grep -o '"setup-token":"[^"]*"' | cut -d'"' -f4 || echo "")

if [ -z "$SETUP_TOKEN" ] || [ "$SETUP_TOKEN" = "null" ]; then
  echo "Metabase is already set up (no setup token), verifying credentials..."

  # Try to authenticate with provided credentials
  SESSION_RESPONSE=$(curl -s -X POST "${METABASE_URL}/api/session" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${METABASE_ADMIN_EMAIL}\",\"password\":\"${METABASE_ADMIN_PASSWORD}\"}")

  SESSION_ID=$(echo "$SESSION_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || echo "")

  if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "null" ]; then
    echo "✓ Successfully authenticated with existing credentials"
    echo "Session ID: $SESSION_ID"

    # Configure Google OAuth
    echo "Configuring Google OAuth..."
    GOOGLE_SETTINGS_RESPONSE=$(curl -s -X PUT "${METABASE_URL}/api/google/settings" \
      -H "Content-Type: application/json" \
      -H "X-Metabase-Session: ${SESSION_ID}" \
      -d "{\"google-auth-auto-create-accounts-domain\":null,\"google-auth-enabled\":true,\"google-auth-client-id\":\"${METABASE_GOOGLE_CLIENT_ID}\"}")

    if echo "$GOOGLE_SETTINGS_RESPONSE" | grep -q "google-auth-enabled"; then
      echo "✓ Google OAuth configured successfully"
    else
      echo "⚠ WARNING: Failed to configure Google OAuth"
      echo "Response: $GOOGLE_SETTINGS_RESPONSE"
    fi

    echo "Metabase is ready to use!"
    exit 0
  else
    echo "⚠ WARNING: Metabase is already set up but provided credentials don't work"
    echo "This is expected if Metabase was set up manually or with different credentials"
    echo "Response: $SESSION_RESPONSE"
    # Don't fail - the operator can still work if credentials are correct
    exit 0
  fi
fi

echo "Setup token found, attempting to initialize Metabase..."
echo "Setup token: $SETUP_TOKEN"

# Perform initial setup
SETUP_PAYLOAD=$(cat <<EOF
{
  "token": "${SETUP_TOKEN}",
  "user": {
    "first_name": "Admin",
    "last_name": "User",
    "email": "${METABASE_ADMIN_EMAIL}",
    "password": "${METABASE_ADMIN_PASSWORD}",
    "site_name": "Metabase"
  },
  "prefs": {
    "site_name": "Metabase",
    "site_locale": "en",
    "allow_tracking": false
  }
}
EOF
)

echo "Sending setup request..."
SETUP_RESPONSE=$(curl -s -X POST "${METABASE_URL}/api/setup" \
  -H "Content-Type: application/json" \
  -d "$SETUP_PAYLOAD")

# Check if setup was successful by looking for an id in the response
if echo "$SETUP_RESPONSE" | grep -q '"id"'; then
  echo "✓ Metabase setup completed successfully!"
  echo "Admin email: ${METABASE_ADMIN_EMAIL}"

  # Extract session ID from setup response
  SESSION_ID=$(echo "$SETUP_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || echo "")

  if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "null" ]; then
    echo "Configuring Google OAuth..."
    GOOGLE_SETTINGS_RESPONSE=$(curl -s -X PUT "${METABASE_URL}/api/google/settings" \
      -H "Content-Type: application/json" \
      -H "X-Metabase-Session: ${SESSION_ID}" \
      -d "{\"google-auth-auto-create-accounts-domain\":null,\"google-auth-enabled\":true,\"google-auth-client-id\":\"${METABASE_GOOGLE_CLIENT_ID}\"}")

    if echo "$GOOGLE_SETTINGS_RESPONSE" | grep -q "google-auth-enabled"; then
      echo "✓ Google OAuth configured successfully"
    else
      echo "⚠ WARNING: Failed to configure Google OAuth"
      echo "Response: $GOOGLE_SETTINGS_RESPONSE"
    fi
  fi

  exit 0
fi

# Check if the error is because a user already exists (setup already done)
if echo "$SETUP_RESPONSE" | grep -q "can only be used to create the first user"; then
  echo "✓ Metabase is already set up (user already exists)"

  # Verify we can authenticate
  SESSION_RESPONSE=$(curl -s -X POST "${METABASE_URL}/api/session" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${METABASE_ADMIN_EMAIL}\",\"password\":\"${METABASE_ADMIN_PASSWORD}\"}")

  SESSION_ID=$(echo "$SESSION_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || echo "")

  if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "null" ]; then
    echo "✓ Successfully authenticated with existing credentials"

    # Configure Google OAuth
    echo "Configuring Google OAuth..."
    GOOGLE_SETTINGS_RESPONSE=$(curl -s -X PUT "${METABASE_URL}/api/google/settings" \
      -H "Content-Type: application/json" \
      -H "X-Metabase-Session: ${SESSION_ID}" \
      -d "{\"google-auth-auto-create-accounts-domain\":null,\"google-auth-enabled\":true,\"google-auth-client-id\":\"${METABASE_GOOGLE_CLIENT_ID}\"}")

    if echo "$GOOGLE_SETTINGS_RESPONSE" | grep -q "google-auth-enabled"; then
      echo "✓ Google OAuth configured successfully"
    else
      echo "⚠ WARNING: Failed to configure Google OAuth"
      echo "Response: $GOOGLE_SETTINGS_RESPONSE"
    fi

    echo "Metabase is ready to use!"
    exit 0
  else
    echo "⚠ WARNING: Metabase is already set up but provided credentials don't work"
    echo "Response: $SESSION_RESPONSE"
    exit 0
  fi
fi

# All other errors should fail the job
echo "ERROR: Metabase setup failed"
echo "Response: $SETUP_RESPONSE"

# Check for specific validation errors
if echo "$SETUP_RESPONSE" | grep -q "valid email"; then
  echo "ERROR: Admin email validation failed - check that METABASE_ADMIN_EMAIL is set correctly"
  exit 1
fi
if echo "$SETUP_RESPONSE" | grep -q "password"; then
  echo "ERROR: Password validation failed - check that METABASE_ADMIN_PASSWORD is set and not too common"
  exit 1
fi

exit 1

