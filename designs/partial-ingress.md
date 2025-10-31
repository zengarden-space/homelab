# PartialIngress Design

## Overview

A Kubernetes operator that enables **partial environment deployments** by automatically replicating Ingress routes from base environments. Deploy only the microservices you changed in a PR environment, and automatically route other requests to existing dev/staging environments.

## Problem Statement

In microservices architectures, testing a single service typically requires deploying the entire stack:

**Traditional Approach:**
- Deploy ALL microservices for each PR
- Resource-intensive (10 services × 5 PRs = 50 deployments)
- Slow build and deployment times
- Complex dependency management

**Desired Approach:**
- Deploy ONLY the changed microservice(s) in PR environment
- Automatically route other requests to dev environment
- Test integration without full stack deployment

## Solution

Two simple CRDs that work together:

1. **PartialIngress** - Drop-in replacement for `kind: Ingress`
2. **CompositeIngressHost** - Declares hostname pattern and base environment (just 3 fields)

**Operator scans all Ingresses for the base hostname and replicates their paths to PR environments, unless overridden by PartialIngress.**

## Core Concepts

### CompositeIngressHost

Each microservice deploys a **CompositeIngressHost** with identical values. Operator automatically deduplicates them.

```yaml
apiVersion: networking.zengarden.space/v1
kind: CompositeIngressHost
metadata:
  name: retroboard-composite
  namespace: dev-retroboard  # Each microservice in its own namespace

spec:
  # Base hostname (e.g., dev environment)
  baseHost: "retroboard.zengarden.space"

  # Pattern for PR environments (glob pattern, e.g., * or ci-*)
  hostPattern: "retroboard-*.zengarden.space"

  # Ingress class to match
  ingressClassName: internal
```

**That's it!** No service lists, no hardcoded namespaces, no conventions.

### PartialIngress

Replace `kind: Ingress` with `kind: PartialIngress` in CI/PR environments. Everything else stays the same.

```yaml
apiVersion: networking.zengarden.space/v1
kind: PartialIngress
metadata:
  name: retroboard
  namespace: ci-feat-oauth-retroboard

spec:
  # Identical to Ingress spec
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

## How It Works

### 1. Operator Scans Ingresses

For each unique `CompositeIngressHost` (deduplicated by baseHost + hostPattern + ingressClassName):

1. Find all `Ingress` resources where:
   - `spec.ingressClassName` matches
   - `spec.rules[].host` matches `baseHost`

2. Collect all paths from those Ingresses with their backends

### 2. Operator Matches PartialIngress

For each `PartialIngress`:

1. Extract hostname from `spec.rules[].host`
2. Match against `CompositeIngressHost.hostPattern`
3. Identify which paths are provided locally

### 3. Operator Generates Ingresses

For matched `PartialIngress`:

1. Generate Ingress in PartialIngress namespace from PartialIngress spec
2. Find base environment Ingresses that are NOT overridden by PartialIngress
3. Replicate those Ingresses into their original namespaces with the new hostname

**Result:** Multiple Ingresses in different namespaces, all with same hostname. Nginx Ingress Controller merges them automatically.

**No proxy needed!** Just standard Kubernetes Ingress resources.

## Complete Example

### Dev Environment Setup

**retroboard (frontend) deployment:**

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

**retroboard-api (backend) deployment:**

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
# CompositeIngressHost (identical values)
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

**Operator deduplicates:** Both `CompositeIngressHost` resources have identical spec → treated as one logical entity.

### CI/PR Environment

**Deploy ONLY frontend with PartialIngress:**

```yaml
# PartialIngress (same spec as Ingress)
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

**No retroboard-api deployment in CI!** Operator will replicate it automatically.

### Operator Output

**Generated Ingress in CI namespace (from PartialIngress):**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: retroboard
  namespace: ci-feat-oauth-retroboard
  ownerReferences:
    - apiVersion: networking.zengarden.space/v1
      kind: PartialIngress
      name: retroboard

spec:
  ingressClassName: internal

  tls:
  - hosts:
    - retroboard-ci-feat-oauth.zengarden.space
    secretName: retroboard-tls

  rules:
  - host: retroboard-ci-feat-oauth.zengarden.space
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: retroboard  # Local service in ci-feat-oauth-retroboard
            port:
              number: 80
---
# Generated Ingress in dev-retroboard-api namespace (replicated!)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: retroboard-api-6c3f8a9b  # Hash of hostname + ingressClass
  namespace: dev-retroboard-api  # Original namespace where CIH resides!
  annotations:
    partial-ingress.zengarden.space/replicated-for: "retroboard-ci-feat-oauth.zengarden.space"
    partial-ingress.zengarden.space/source-partial-ingress: "ci-feat-oauth-retroboard/retroboard"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Copied from original
  ownerReferences:
    - apiVersion: networking.zengarden.space/v1
      kind: CompositeIngressHost
      name: retroboard-composite
      # Owned by CIH in same namespace (cannot cross namespaces)

spec:
  ingressClassName: internal

  tls:
  - hosts:
    - retroboard-ci-feat-oauth.zengarden.space
    secretName: retroboard-tls-6c3f8a9b  # Hash appended to secret name

  rules:
  - host: retroboard-ci-feat-oauth.zengarden.space  # New hostname!
    http:
      paths:
      # Same paths as original dev Ingress
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: retroboard-api  # Local service in dev-retroboard-api
            port:
              number: 80

      - path: /graphql
        pathType: Prefix
        backend:
          service:
            name: retroboard-api
            port:
              number: 80
```

**Hash-based naming:**
- Hash = first 8 chars of SHA256(hostname + ingressClassName)
- Example: `6c3f8a9b` = SHA256(`retroboard-ci-feat-oauth.zengarden.space:internal`)[:8]
- Ingress name: `<original-name>-<hash>`
- TLS secret name: `<original-secret>-<hash>` (same hash)
- cert-manager generates new certificate for the new hostname

**Result:** Two Ingresses in different namespaces, same hostname. Nginx merges them.

- `GET /` → retroboard in ci-feat-oauth-retroboard namespace
- `POST /api/boards` → retroboard-api in dev-retroboard-api namespace
- `POST /graphql` → retroboard-api in dev-retroboard-api namespace

**TLS certificates:**
- `retroboard-tls` in ci-feat-oauth-retroboard (for CI frontend)
- `retroboard-tls-6c3f8a9b` in dev-retroboard-api (generated by cert-manager for replicated Ingress)

## Request Flow

```
User: https://retroboard-ci-feat-oauth.zengarden.space/api/boards
         ↓
Nginx Ingress Controller (TLS termination)
         ↓
Matches Ingress in dev-retroboard-api namespace, path /api
         ↓
Routes to service: retroboard-api.dev-retroboard-api.svc:80
         ↓
retroboard-api pod in dev environment handles request
```

## Environment Agnostic

### Fallback to Staging Instead of Dev

Simply change the `baseHost` in `CompositeIngressHost`:

```yaml
apiVersion: networking.zengarden.space/v1
kind: CompositeIngressHost
metadata:
  name: retroboard-composite
  namespace: ci-feat-oauth-retroboard

spec:
  baseHost: "retroboard.staging.zengarden.space"  # Points to staging!
  hostPattern: "retroboard-*.staging.zengarden.space"
  ingressClassName: internal
```

Operator scans Ingresses in staging environment instead.

### Multiple Environments Simultaneously

CI environment can mix services from dev and staging:

```yaml
# retroboard fallback to dev
apiVersion: networking.zengarden.space/v1
kind: CompositeIngressHost
metadata:
  name: retroboard-dev-composite
  namespace: ci-mixed-retroboard
spec:
  baseHost: "retroboard.dev.zengarden.space"
  hostPattern: "retroboard-*.zengarden.space"
  ingressClassName: internal
---
# retroboard-api fallback to staging
apiVersion: networking.zengarden.space/v1
kind: CompositeIngressHost
metadata:
  name: retroboard-staging-composite
  namespace: ci-mixed-retroboard-api
spec:
  baseHost: "retroboard.staging.zengarden.space"
  hostPattern: "retroboard-*.zengarden.space"
  ingressClassName: internal
```

## CI/CD Integration

### Helm Chart Migration

**Change one line:**

```yaml
# Before
apiVersion: networking.k8s.io/v1
kind: Ingress

# After
apiVersion: networking.zengarden.space/v1
kind: PartialIngress
```

**Or use Helm conditionals:**

```yaml
{{- if .Values.ci.enabled }}
apiVersion: networking.zengarden.space/v1
kind: PartialIngress
{{- else }}
apiVersion: networking.k8s.io/v1
kind: Ingress
{{- end }}
```

### Gitea Actions Workflow

**Build-time substitution:**

```bash
helm template myapp ./helm/myapp \
  --set ingress.host="myapp-ci-${BRANCH}.zengarden.space" \
  > manifest.yaml

# Substitute Ingress → PartialIngress
sed -i 's/kind: Ingress/kind: PartialIngress/g' manifest.yaml
```

## Progressive Override

Deploy more services as needed:

**Scenario 1: Deploy only frontend**
- `PartialIngress` for retroboard
- Operator replicates retroboard-api from dev

**Scenario 2: Deploy frontend + backend**
- `PartialIngress` for retroboard
- `PartialIngress` for retroboard-api
- No replication needed (both deployed in CI)

**Scenario 3: Deploy entire stack**
- `PartialIngress` for all services
- Behaves like normal deployment (no fallbacks)

## Benefits

### For Developers
✅ Deploy only changed microservices
✅ Test integration with real dev/staging backends
✅ Fast deployment (build 1 service vs 10)
✅ Predictable URLs: `<app>-ci-<branch>.domain.com`

### For Operations
✅ Resource efficiency (90% savings per PR environment)
✅ No service discovery complexity
✅ Works with any environment (dev/staging/prod)
✅ Standard Kubernetes primitives (no custom proxy)

### For Platform
✅ Zero conventions or hardcoded logic
✅ Automatic Ingress scanning and discovery
✅ Declarative (each microservice declares its own config)
✅ Deduplication prevents conflicts

## Architecture Components

1. **PartialIngress CRD** - Drop-in Ingress replacement
2. **CompositeIngressHost CRD** - 3-field configuration (baseHost, hostPattern, ingressClassName)
3. **Operator** - Scans Ingresses, generates complete routing

**No proxy or ExternalName services needed!** Just standard Kubernetes Ingress resources.

## Limitations

### TLS Certificate Management

Each PR environment needs its own TLS certificate. Ensure cert-manager is configured:

```yaml
tls:
- hosts:
  - myapp-ci-${BRANCH}.zengarden.space
  secretName: myapp-ci-${BRANCH}-tls

annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

### DNS Wildcard Records

Requires wildcard DNS for PR hostnames:

```
*.zengarden.space → Ingress LoadBalancer IP
```

Or use external-dns to create records dynamically.

## Future Enhancements

1. **Health Checks** - Mark replicated services as unhealthy if base environment is down
2. **Multi-Cluster** - Replicate Ingresses from services in different clusters
3. **Observability** - Dashboards showing which PR uses which base services
4. **Cost Tracking** - Calculate resource savings per PR environment
5. **Automatic Cleanup** - Remove old PartialIngress resources when PRs close

## Design Principles

✅ **Simple** - Just 2 CRDs, minimal configuration
✅ **Declarative** - No imperative logic or conventions
✅ **Flexible** - Works with any environment and namespace layout
✅ **Standard** - Uses normal Kubernetes Ingress + Services
✅ **Automatic** - Operator discovers and replicates without hardcoding