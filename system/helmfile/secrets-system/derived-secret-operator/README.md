# DerivedSecret Operator Helm Chart

Kubernetes operator that derives secrets deterministically from a master password using Argon2id KDF.

## Features

- 🔐 **Cryptographically secure**: Uses Argon2id (memory-hard KDF)
- 🔄 **Deterministic**: Same input always produces same output
- 🎯 **Flexible**: Generate secrets of any length (Base62: A-Za-z0-9)
- 🚀 **Non-root**: Runs with strict security contexts
- ♻️ **GitOps friendly**: CRD-based declarative configuration
- 📁 **Simple IPC**: File-based communication (works with BusyBox/Alpine)

## Architecture

- **StatefulSet**: Single-replica operator with stable storage for pip packages
- **Shell-operator**: Watches DerivedSecret CRDs across all namespaces
- **Bash hook**: Writes binding context to `/shared` directory
- **Python handler**: Watches for request files, derives secrets using Argon2id, creates/updates Kubernetes Secrets
- **File-based IPC**: No sockets, no HTTP - just simple file read/write
- **Automatic PVC**: Each pod gets a 200Mi PersistentVolumeClaim for faster restarts

## Installation

### Prerequisites

- Kubernetes 1.19+
- Helm 3+

### What Happens to Existing Secrets?

The operator handles existing secrets intelligently:

- **Secret exists**: The operator **merges** derived values with existing keys
- **Secret doesn't exist**: The operator **creates** a new secret
- **Preserves unmanaged keys**: Keys not specified in DerivedSecret are preserved
- **Overrides only specified keys**: Only the keys defined in the DerivedSecret spec are updated
- **Deterministic behavior**: The same DerivedSecret spec always produces the same secret values
- **Safe updates**: Secrets are updated atomically using Kubernetes' replace operation

**Example:**
```yaml
# Existing secret has: username, password, manualKey
# DerivedSecret specifies: password, apiKey
# Result: username ✓ (preserved), password ✓ (overridden), manualKey ✓ (preserved), apiKey ✓ (added)
```

**Important notes:**
- If you change the master password, all secrets will be re-derived with different values on next sync
- Deleting a DerivedSecret does NOT delete the generated Kubernetes Secret (preserves all keys)
- To regenerate secrets, delete the Kubernetes Secret and the operator will recreate it
- Manual keys are safe - they won't be removed when DerivedSecret updates
- The operator uses StatefulSet with automatic PVC management for stability

### Deployment Strategy

The operator runs as a **StatefulSet** with the following benefits:

- **Ordered rollout**: Pods are created/deleted in order (0, 1, 2, etc.)
- **Stable storage**: Each pod gets its own PersistentVolumeClaim for pip packages
- **Automatic cleanup**: On upgrade, old pods are deleted and recreated automatically
- **Parallel updates**: Uses `podManagementPolicy: Parallel` for faster rollouts
- **Persistent identity**: Each pod maintains its storage across restarts

## Entropy Requirements by Use Case

| Use Case | Min Entropy | Min Length (Base62) | Recommended Length |
|----------|-------------|---------------------|-------------------|
| **JWT Secret** | 256 bits | 43 chars | 64 chars |
| **Database Password** | 128 bits | 22 chars | 32 chars |
| **Admin Credentials** | 128 bits | 22 chars | 32 chars |
| **API Keys (public)** | 256 bits | 43 chars | 64 chars |
| **Session Tokens** | 128 bits | 22 chars | 32 chars |
| **Encryption Keys** | 256 bits | 43 chars | 64 chars (or raw binary) |

**Calculation:**
- Base62 (A-Za-z0-9) provides ~5.95 bits of entropy per character
- 128 bits ÷ 5.95 ≈ 21.5 characters → **minimum 22 chars**
- 256 bits ÷ 5.95 ≈ 43 characters → **minimum 43 chars**

**Guidelines:**
- Use **128-bit minimum** for internal/private secrets (databases, admin)
- Use **256-bit minimum** for public-facing secrets (JWT, API keys, encryption)
- Always round up to ensure sufficient entropy
- Add extra length for safety margin (e.g., 32 instead of 22, 64 instead of 43)

## Usage

### Creating a DerivedSecret

The DerivedSecret CRD accepts any field names with integer values representing the desired length of each derived secret:

```yaml
apiVersion: zengarden.space/v1
kind: DerivedSecret
metadata:
  name: my-app
  namespace: secrets
spec:
  adminPassword: 32
  jwtSecret: 64
  databasePassword: 32
  apiKey: 64
```

This will create a Kubernetes Secret named `my-app` in the `secrets` namespace with the following keys:
- `adminPassword`: 32-character derived password
- `jwtSecret`: 64-character derived secret
- `databasePassword`: 32-character derived password
- `apiKey`: 64-character derived key

### How It Works

Each secret is derived deterministically using:
- **Master password**: Set in the operator configuration
- **Namespace**: The namespace of the DerivedSecret
- **Name**: The name of the DerivedSecret
- **Key name**: The field name (e.g., `adminPassword`, `jwtSecret`)

**Flow:**
1. Shell-operator detects DerivedSecret create/update
2. Bash hook writes binding context JSON to `/shared/request-{id}.json`
3. Python handler watches `/shared`, reads request, processes all objects
4. For each DerivedSecret: derives secrets using Argon2id, creates/updates Kubernetes Secret
5. Python writes response to `/shared/response-{id}.txt`
6. Bash hook reads response and exits

This means:
- The same DerivedSecret will always produce the same secrets
- Different key names in the same DerivedSecret will produce different secrets
- DerivedSecrets with different names or namespaces will produce different secrets
- The secrets are cryptographically secure and cannot be reverse-engineered without the master password

### Example: Application Secrets

```yaml
apiVersion: zengarden.space/v1
kind: DerivedSecret
metadata:
  name: webapp
  namespace: production
spec:
  DATABASE_PASSWORD: 32
  JWT_SECRET: 64
  SESSION_SECRET: 32
  ENCRYPTION_KEY: 64
  API_KEY: 64
```

The generated Secret can then be used in your application:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: production
spec:
  template:
    spec:
      containers:
      - name: webapp
        image: myapp:latest
        envFrom:
        - secretRef:
            name: webapp  # References the generated Secret
```

### Updating Secrets

To update derived secrets:

1. **Change DerivedSecret spec**: Add/remove/modify fields - operator updates the Secret
2. **Rotate all secrets**: Change the master password - all secrets regenerate
3. **Force regeneration**: Delete the Kubernetes Secret - operator recreates it

The operator watches for DerivedSecret changes and automatically updates the corresponding Kubernetes Secrets. Since derivation is deterministic, the same spec always produces the same values (unless the master password changes).

### Constraints

- Minimum length: **8 characters**
- Maximum length: **128 characters**
- Only integer values are accepted
- Secret keys must be valid Kubernetes secret key names