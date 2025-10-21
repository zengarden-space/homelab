# Gitea Runner Helm Chart

This Helm chart deploys Gitea Action Runners with automatic token generation.

## Features

- **Automatic Token Generation**: Uses kubectl exec to run `gitea actions generate-runner-token` inside a Gitea pod
- **RBAC Security**: Includes proper ServiceAccount, Role, RoleBinding, ClusterRole, and ClusterRoleBinding for secure operation
- **Configurable**: All major settings can be configured via values.yaml
- **Image Pull Secrets**: Supports private registry authentication

## Components

### 1. Token Generator Job (`job.yaml`)
- Runs as a Kubernetes Job
- Finds a running Gitea pod in the `gitea` namespace
- Executes `gitea actions generate-runner-token` via kubectl exec
- Creates the `gitea-action-runner` secret with the generated token

### 2. RBAC Resources (`rbac.yaml`)
- ServiceAccount: `gitea-token-generator`
- Role: Permissions to manage secrets in the current namespace
- ClusterRole: Permissions to list pods and exec into pods in any namespace
- RoleBinding and ClusterRoleBinding: Links the ServiceAccount to the respective roles

### 3. Runner StatefulSet (`statefulset.yaml`)
- Runs multiple Gitea Action Runner instances
- Uses Docker-in-Docker for action execution
- References the auto-generated token secret

### 4. Cache Server (`deployment.yaml`)
- Provides caching for runner actions
- Improves performance by caching dependencies

## Configuration

### Values.yaml Options

```yaml
gitea:
  url: "https://gitea.homelab.int.zengarden.space"
  image: "docker.gitea.com/gitea:1.23.8-rootless"

runner:
  replicas: 5
  image: "gitea/act_runner:0.2.11"

imagePullSecrets: {}

imagePullSecrets:
  - name: docker-hub
```

## Usage

1. Deploy the chart:
```bash
helm install gitea-runner ./charts/gitea-runner -n gitea
```

2. The token generation job will run automatically and create the required secret

3. Runner pods will start and register with your Gitea instance

## Token Generation Process

1. The Job waits for Gitea to be available
2. Generates a UUID-based token (placeholder implementation)
3. Creates the `gitea-action-runner` secret with the token
4. Runner pods use this secret to register with Gitea

## Security

- All containers run with restricted security contexts
- RBAC follows principle of least privilege
- No privileged access for token generation
- Docker-in-Docker runs with necessary privileges only

## Future Enhancements

- Integrate with actual Gitea API for proper token generation
- Add support for organization-specific tokens
- Implement token rotation mechanism
