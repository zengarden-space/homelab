# PartialIngress Operator Helm Chart

Kubernetes operator that enables **partial environment deployments** by automatically replicating Ingress routes from base environments. Deploy only the microservices you changed in a PR environment, and automatically route other requests to existing dev/staging environments.

## Features

- 🚀 **Partial Deployments**: Deploy only changed services, fallback to base environment for others
- 🔄 **Automatic Ingress Replication**: Scans base Ingresses and replicates them with new hostnames
- 🎯 **Zero Conventions**: No hardcoded namespaces or service names
- 🔐 **Non-root**: Runs with strict security contexts
- ♻️ **GitOps friendly**: CRD-based declarative configuration
- 🌐 **Environment Agnostic**: Fallback to dev, staging, or mix both

## Architecture

- **StatefulSet**: Single-replica operator with stable storage for pip packages
- **Shell-operator**: Watches PartialIngress and CompositeIngressHost CRDs across all namespaces
- **Bash hook**: Writes binding context to `/shared` directory
- **Python handler**: Processes CRD events, scans base Ingresses, generates replicated Ingresses
- **File-based IPC**: No sockets, no HTTP - just simple file read/write
- **Automatic PVC**: Each pod gets a 200Mi PersistentVolumeClaim for faster restarts

## Installation

### Prerequisites

- Kubernetes 1.19+
- Helm 3+
- nginx-ingress-controller (or any Ingress controller that supports multiple Ingresses per hostname)

### Installing the Chart

```bash
helm install partial-ingress-operator ./partial-ingress-operator \
  --namespace ingress-nginx \
  --create-namespace
```

## Usage

### Core Concepts

#### 1. CompositeIngressHost

Declares the base environment and hostname pattern. Each microservice deploys an identical CompositeIngressHost - the operator automatically deduplicates them.

```yaml
apiVersion: networking.zengarden.space/v1
kind: CompositeIngressHost
metadata:
  name: retroboard-composite
  namespace: dev-retroboard  # Each microservice in its own namespace
spec:
  # Base hostname (e.g., dev environment)
  baseHost: "retroboard.zengarden.space"

  # Pattern for PR environments (glob pattern)
  hostPattern: "retroboard-*.zengarden.space"

  # Ingress class to match
  ingressClassName: internal
```

#### 2. PartialIngress

Drop-in replacement for `kind: Ingress`. The spec is **identical** to Ingress spec.

```yaml
apiVersion: networking.zengarden.space/v1
kind: PartialIngress
metadata:
  name: retroboard
  namespace: ci-feat-oauth-retroboard
spec:
  # Identical to Ingress spec!
  ingressClassName: internal
  rules:
  - host: retroboard-ci-feat-oauth.zengarden.space
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: retroboard
            port:
              number: 80
  tls:
  - hosts:
    - retroboard-ci-feat-oauth.zengarden.space
    secretName: retroboard-tls
```

### How It Works

1. **Operator scans base Ingresses**: Finds all Ingress resources where `spec.rules[].host` matches `baseHost` and `spec.ingressClassName` matches
2. **Operator matches PartialIngress**: Extracts hostname from PartialIngress, matches against `hostPattern`
3. **Operator generates Ingresses**:
   - Creates Ingress from PartialIngress spec in same namespace
   - Replicates non-overridden base Ingresses to their **original namespaces** with new hostname
   - Nginx merges Ingresses automatically (same hostname, different namespaces)

**Result**: Multiple Ingresses in different namespaces, all with same hostname. No proxy needed!

### Complete Example

#### Dev Environment (Base)

**Frontend (dev-retroboard namespace):**
```yaml
# Standard Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: retroboard
  namespace: dev-retroboard
spec:
  ingressClassName: internal
  rules:
  - host: retroboard.zengarden.space
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: retroboard
            port:
              number: 80
---
# CompositeIngressHost
apiVersion: networking.zengarden.space/v1
kind: CompositeIngressHost
metadata:
  name: retroboard-composite
  namespace: dev-retroboard
spec:
  baseHost: "retroboard.zengarden.space"
  hostPattern: "retroboard-*.zengarden.space"
  ingressClassName: internal
```

**Backend (dev-retroboard-api namespace):**
```yaml
# Standard Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: retroboard-api
  namespace: dev-retroboard-api
spec:
  ingressClassName: internal
  rules:
  - host: retroboard.zengarden.space  # Same host!
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: retroboard-api
            port:
              number: 80
      - path: /graphql
        pathType: Prefix
        backend:
          service:
            name: retroboard-api
            port:
              number: 80
---
# CompositeIngressHost (identical)
apiVersion: networking.zengarden.space/v1
kind: CompositeIngressHost
metadata:
  name: retroboard-composite
  namespace: dev-retroboard-api
spec:
  baseHost: "retroboard.zengarden.space"
  hostPattern: "retroboard-*.zengarden.space"
  ingressClassName: internal
```

#### CI/PR Environment (Deploy ONLY Frontend)

```yaml
# PartialIngress (only frontend deployed in CI)
apiVersion: networking.zengarden.space/v1
kind: PartialIngress
metadata:
  name: retroboard
  namespace: ci-feat-oauth-retroboard
spec:
  ingressClassName: internal
  rules:
  - host: retroboard-ci-feat-oauth.zengarden.space
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: retroboard
            port:
              number: 80
  tls:
  - hosts:
    - retroboard-ci-feat-oauth.zengarden.space
    secretName: retroboard-tls
---
# CompositeIngressHost (same as dev)
apiVersion: networking.zengarden.space/v1
kind: CompositeIngressHost
metadata:
  name: retroboard-composite
  namespace: ci-feat-oauth-retroboard
spec:
  baseHost: "retroboard.zengarden.space"
  hostPattern: "retroboard-*.zengarden.space"
  ingressClassName: internal
```

**No backend deployment!** Operator automatically replicates backend Ingress:

**Generated by operator:**
```yaml
# Ingress in ci-feat-oauth-retroboard (from PartialIngress)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: retroboard
  namespace: ci-feat-oauth-retroboard
  ownerReferences: [...]
spec:
  ingressClassName: internal
  rules:
  - host: retroboard-ci-feat-oauth.zengarden.space
    http:
      paths:
      - path: /
        backend:
          service:
            name: retroboard  # Local service
---
# Replicated Ingress in dev-retroboard-api namespace!
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: retroboard-api-6c3f8a9b  # Hash appended
  namespace: dev-retroboard-api  # Original namespace!
  annotations:
    partial-ingress.zengarden.space/replicated-for: "ci-feat-oauth-retroboard"
  ownerReferences: [...]
spec:
  ingressClassName: internal
  rules:
  - host: retroboard-ci-feat-oauth.zengarden.space  # New hostname!
    http:
      paths:
      - path: /api
        backend:
          service:
            name: retroboard-api  # Service in dev-retroboard-api
      - path: /graphql
        backend:
          service:
            name: retroboard-api
  tls:
  - hosts:
    - retroboard-ci-feat-oauth.zengarden.space
    secretName: retroboard-tls-6c3f8a9b  # Hash appended
```

**Request flow:**
- `GET /` → retroboard in ci-feat-oauth-retroboard namespace
- `POST /api/boards` → retroboard-api in dev-retroboard-api namespace
- `POST /graphql` → retroboard-api in dev-retroboard-api namespace

### Helm Chart Migration

Change one line in your Helm templates:

```yaml
# Before
apiVersion: networking.k8s.io/v1
kind: Ingress

# After (for CI/PR environments)
apiVersion: networking.zengarden.space/v1
kind: PartialIngress
```

Or use conditionals:

```yaml
{{- if .Values.ci.enabled }}
apiVersion: networking.zengarden.space/v1
kind: PartialIngress
{{- else }}
apiVersion: networking.k8s.io/v1
kind: Ingress
{{- end }}
```

### Benefits

- **90% resource savings** per PR environment
- **Faster deployments** - build 1 service vs 10
- **Integration testing** - test against real dev/staging backends
- **No service discovery** - uses standard Kubernetes Ingress
- **Environment agnostic** - works with any namespace layout

## Configuration

See [values.yaml](values.yaml) for full configuration options.

Key settings:

```yaml
operator:
  replicaCount: 1
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"

handlerSidecar:
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
```

## Troubleshooting

### View operator logs

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=partial-ingress-operator -c handler-service
```

### List PartialIngresses

```bash
kubectl get partialingresses --all-namespaces
kubectl get ping --all-namespaces  # shorthand
```

### List CompositeIngressHosts

```bash
kubectl get compositeingresshosts --all-namespaces
kubectl get cih --all-namespaces  # shorthand
```

### Check status

```bash
kubectl describe partialingress <name> -n <namespace>
kubectl describe compositeingresshost <name> -n <namespace>
```

## Limitations

1. **TLS certificates**: Each PR hostname needs its own certificate. Use cert-manager with annotations.
2. **DNS wildcards**: Requires wildcard DNS or external-dns for PR hostnames.
3. **Path matching**: Currently uses simple string comparison. Complex path matching (overlapping paths) may not work as expected.

## Design

See [designs/partial-ingress.md](../../../../../designs/partial-ingress.md) for full design documentation.
