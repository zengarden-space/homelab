#!/usr/bin/env python3
"""
RBAC Operator Service
Watches User CRDs and ClusterRoles to automatically create RoleBindings
"""

import os
import sys
import json
import time
import signal
from datetime import datetime
from kubernetes import client, config
from typing import Dict, List, Set, Optional


# Global flag for graceful shutdown
shutdown_requested = False


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    global shutdown_requested
    print(f"\n[shutdown] Received signal {signum}, initiating graceful shutdown...", flush=True)
    shutdown_requested = True


class RBACOperatorService:
    """Main service for managing RBAC based on Users and ClusterRoles"""

    def __init__(self):
        # Load Kubernetes config from service account
        config.load_incluster_config()
        self.v1 = client.CoreV1Api()
        self.rbac_v1 = client.RbacAuthorizationV1Api()
        self.custom_api = client.CustomObjectsApi()

        print("RBAC Operator Service initialized", flush=True)

    def get_all_users(self) -> List[Dict]:
        """Get all User CRDs"""
        try:
            result = self.custom_api.list_cluster_custom_object(
                group='zengarden.space',
                version='v1',
                plural='users'
            )
            return result.get('items', [])
        except Exception as e:
            print(f"WARNING: Failed to list users: {e}", file=sys.stderr, flush=True)
            return []

    def get_argocd_application_namespaces(self) -> Set[str]:
        """Get all namespaces where ArgoCD applications are deployed"""
        namespaces = set()
        try:
            applications = self.custom_api.list_cluster_custom_object(
                group='argoproj.io',
                version='v1alpha1',
                plural='applications'
            )

            for app in applications.get('items', []):
                try:
                    dest_namespace = app.get('spec', {}).get('destination', {}).get('namespace')
                    if dest_namespace:
                        namespaces.add(dest_namespace)
                except Exception as e:
                    print(f"WARNING: Failed to parse application: {e}", file=sys.stderr, flush=True)

        except Exception as e:
            print(f"WARNING: Failed to list ArgoCD applications: {e}", file=sys.stderr, flush=True)

        return namespaces

    def get_cluster_roles_with_namespaces(self) -> Dict[str, List[str]]:
        """
        Get ClusterRoles with zengarden.space/role annotation
        Returns dict mapping role name to list of namespaces
        """
        role_namespaces = {}
        argocd_namespaces = None  # Lazy load when needed

        try:
            # List all ClusterRoles
            cluster_roles = self.rbac_v1.list_cluster_role()

            for cr in cluster_roles.items:
                if not cr.metadata.annotations:
                    continue

                # Get role from annotation
                role_annotation = cr.metadata.annotations.get('zengarden.space/role')
                if not role_annotation:
                    continue

                # Get namespaces from annotation
                namespaces_str = cr.metadata.annotations.get('zengarden.space/namespaces', '')
                if not namespaces_str:
                    print(f"WARNING: ClusterRole {cr.metadata.name} has role annotation but no namespaces annotation", flush=True)
                    continue

                # Parse comma-separated namespaces
                namespace_parts = [ns.strip() for ns in namespaces_str.split(',') if ns.strip()]

                namespaces = []
                for part in namespace_parts:
                    if part == '@argocd':
                        # Lazy load ArgoCD namespaces
                        if argocd_namespaces is None:
                            argocd_namespaces = self.get_argocd_application_namespaces()
                            print(f"Discovered {len(argocd_namespaces)} namespaces from ArgoCD Applications", flush=True)
                        namespaces.extend(argocd_namespaces)
                    else:
                        # Static namespace
                        namespaces.append(part)

                if namespaces:
                    role_namespaces[role_annotation] = namespaces
                    print(f"Found ClusterRole for role '{role_annotation}': {len(namespaces)} namespaces", flush=True)

        except Exception as e:
            print(f"ERROR: Failed to list ClusterRoles: {e}", file=sys.stderr, flush=True)

        return role_namespaces

    def reconcile_user(self, user: Dict):
        """Reconcile RoleBindings for a single user"""
        try:
            metadata = user.get('metadata', {})
            spec = user.get('spec', {})

            user_name = metadata.get('name')
            email = spec.get('email')
            roles = spec.get('roles', [])
            enabled = spec.get('enabled', True)

            print(f"Reconciling user: {user_name} ({email}) with roles: {roles}, enabled: {enabled}", flush=True)

            # Get role-to-namespaces mapping from ClusterRoles
            role_namespaces = self.get_cluster_roles_with_namespaces()

            created_bindings = {}

            # Process each role
            for role in roles:
                if role not in role_namespaces:
                    print(f"WARNING: Role '{role}' not found in ClusterRoles with zengarden.space/role label", flush=True)
                    continue

                namespaces = role_namespaces[role]
                cluster_role_name = f"homelab:{role}"

                print(f"  Managing RoleBindings for role '{role}' in {len(namespaces)} namespaces", flush=True)

                for ns in namespaces:
                    binding_name = f"homelab:{role}:{user_name}"
                    try:
                        self.ensure_rolebinding(
                            namespace=ns,
                            name=binding_name,
                            cluster_role=cluster_role_name,
                            subject_email=email,
                            user_name=user_name,
                            role=role,
                            user_metadata=metadata,
                            enabled=enabled
                        )
                        if enabled:
                            created_bindings.setdefault(ns, []).append(binding_name)
                    except Exception as e:
                        print(f"ERROR managing RoleBinding {ns}/{binding_name}: {e}", file=sys.stderr, flush=True)

            # Update User status
            self.update_user_status(user_name, created_bindings, success=True)

            print(f"✓ Successfully reconciled user: {user_name}", flush=True)

        except Exception as e:
            print(f"ERROR reconciling user {user.get('metadata', {}).get('name')}: {e}", file=sys.stderr, flush=True)
            import traceback
            traceback.print_exc()

            # Update status with error
            try:
                self.update_user_status(
                    user.get('metadata', {}).get('name'),
                    {},
                    success=False,
                    error=str(e)
                )
            except:
                pass

    def ensure_rolebinding(self, namespace: str, name: str, cluster_role: str, subject_email: str, user_name: str, role: str, user_metadata: Dict, enabled: bool = True):
        """Create or update a RoleBinding, managing subject presence based on enabled flag"""
        try:
            # Check if RoleBinding exists
            try:
                existing = self.rbac_v1.read_namespaced_role_binding(name=name, namespace=namespace)
                print(f"  RoleBinding exists: {namespace}/{name}", flush=True)

                # Check if subject exists
                subjects = existing.subjects or []
                subject_exists = any(
                    s.kind == 'User' and s.name == subject_email
                    for s in subjects
                )

                needs_update = False

                if enabled and not subject_exists:
                    # Add subject if user is enabled
                    subjects.append(client.RbacV1Subject(
                        kind='User',
                        name=subject_email,
                        api_group='rbac.authorization.k8s.io'
                    ))
                    needs_update = True
                    print(f"  Adding user to RoleBinding: {namespace}/{name}", flush=True)
                elif not enabled and subject_exists:
                    # Remove subject if user is disabled
                    subjects = [s for s in subjects if not (s.kind == 'User' and s.name == subject_email)]
                    needs_update = True
                    print(f"  Removing user from RoleBinding: {namespace}/{name}", flush=True)

                if needs_update:
                    existing.subjects = subjects if subjects else None
                    self.rbac_v1.replace_namespaced_role_binding(
                        name=name,
                        namespace=namespace,
                        body=existing
                    )
                    print(f"  Updated RoleBinding: {namespace}/{name}", flush=True)

                return

            except client.rest.ApiException as e:
                if e.status != 404:
                    raise

            # RoleBinding doesn't exist - only create if user is enabled
            if not enabled:
                print(f"  User disabled, skipping creation of RoleBinding: {namespace}/{name}", flush=True)
                return

            # Create ownerReference to User CRD
            owner_references = [
                client.V1OwnerReference(
                    api_version='zengarden.space/v1',
                    kind='User',
                    name=user_metadata.get('name'),
                    uid=user_metadata.get('uid'),
                    block_owner_deletion=True,
                    controller=True
                )
            ]

            # Create new RoleBinding
            role_binding = client.V1RoleBinding(
                metadata=client.V1ObjectMeta(
                    name=name,
                    namespace=namespace,
                    labels={
                        'app.kubernetes.io/managed-by': 'rbac-operator',
                        'zengarden.space/role': role,
                        'zengarden.space/user': user_name
                    },
                    owner_references=owner_references
                ),
                role_ref=client.V1RoleRef(
                    api_group='rbac.authorization.k8s.io',
                    kind='ClusterRole',
                    name=cluster_role
                ),
                subjects=[
                    client.RbacV1Subject(
                        kind='User',
                        name=subject_email,
                        api_group='rbac.authorization.k8s.io'
                    )
                ]
            )

            self.rbac_v1.create_namespaced_role_binding(
                namespace=namespace,
                body=role_binding
            )
            print(f"  Created RoleBinding: {namespace}/{name}", flush=True)

        except Exception as e:
            print(f"ERROR managing RoleBinding {namespace}/{name}: {e}", file=sys.stderr, flush=True)
            raise

    def update_user_status(self, user_name: str, role_bindings: Dict[str, List[str]], success: bool = True, error: str = None):
        """Update User status"""
        timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

        conditions = []
        if success:
            conditions.append({
                'type': 'Ready',
                'status': 'True',
                'lastTransitionTime': timestamp,
                'reason': 'ReconciliationSucceeded',
                'message': f'Successfully created {sum(len(v) for v in role_bindings.values())} RoleBindings'
            })
        else:
            conditions.append({
                'type': 'Ready',
                'status': 'False',
                'lastTransitionTime': timestamp,
                'reason': 'ReconciliationFailed',
                'message': error or 'Unknown error'
            })

        status = {
            'status': {
                'conditions': conditions,
                'roleBindings': role_bindings,
                'lastUpdated': timestamp
            }
        }

        try:
            self.custom_api.patch_namespaced_custom_object_status(
                group='zengarden.space',
                version='v1',
                plural='users',
                namespace='',  # Cluster-scoped
                name=user_name,
                body=status
            )
            print(f"Updated status for User: {user_name}", flush=True)
        except Exception as e:
            print(f"WARNING: Failed to update User status: {e}", file=sys.stderr, flush=True)

    def reconcile_all(self):
        """Reconcile all users"""
        print("\n=== Starting full reconciliation ===", flush=True)

        users = self.get_all_users()
        print(f"Found {len(users)} users to reconcile", flush=True)

        for user in users:
            if shutdown_requested:
                print("[shutdown] Stopping reconciliation...", flush=True)
                break

            self.reconcile_user(user)

        # Sync ArgoCD RBAC if argocd namespace exists
        self.sync_argocd_rbac(users)

        print("=== Reconciliation complete ===\n", flush=True)

    def sync_argocd_rbac(self, users: List[Dict]):
        """Generate and update ArgoCD RBAC ConfigMap if argocd namespace exists"""
        try:
            # Check if argocd namespace exists
            try:
                self.v1.read_namespace(name='argocd')
            except client.rest.ApiException as e:
                if e.status == 404:
                    print("ArgoCD namespace does not exist, skipping RBAC sync", flush=True)
                    return
                raise

            print("Syncing ArgoCD RBAC ConfigMap", flush=True)

            # Build policy.csv content
            policy_lines = []

            # Add role definitions (static)
            # NOTE: Roles are hierarchical - users should only have ONE role assigned
            # Higher roles inherit lower role permissions
            policy_lines.extend([
                "# ============================================",
                "# Application Developer Role",
                "# ============================================",
                "# Can work with apps in the 'apps' project only",
                "p, role:app-developer, applications, get, apps/*, allow",
                "p, role:app-developer, applications, sync, apps/*, allow",
                "p, role:app-developer, applications, override, apps/*, allow",
                "p, role:app-developer, applications, action/*, apps/*, allow",
                "p, role:app-developer, logs, get, apps/*, allow",
                "p, role:app-developer, exec, create, apps/*, allow",
                "",
                "# ============================================",
                "# Platform Operator Role",
                "# ============================================",
                "# Full access to apps project",
                "p, role:platform-operator, applications, *, apps/*, allow",
                "p, role:platform-operator, logs, get, */*, allow",
                "p, role:platform-operator, exec, create, */*, allow",
                "",
                "# Can view default project apps (but not modify)",
                "p, role:platform-operator, applications, get, default/*, allow",
                "",
                "# Can manage projects and repositories",
                "p, role:platform-operator, projects, get, *, allow",
                "p, role:platform-operator, projects, create, *, allow",
                "p, role:platform-operator, projects, update, *, allow",
                "p, role:platform-operator, repositories, get, *, allow",
                "p, role:platform-operator, repositories, create, *, allow",
                "p, role:platform-operator, repositories, update, *, allow",
                "",
                "# ============================================",
                "# System Administrator Role",
                "# ============================================",
                "# Full access to all projects and ArgoCD management",
                "p, role:system-admin, applications, *, */*, allow",
                "p, role:system-admin, logs, *, */*, allow",
                "p, role:system-admin, exec, *, */*, allow",
                "p, role:system-admin, projects, *, *, allow",
                "p, role:system-admin, repositories, *, *, allow",
                "p, role:system-admin, certificates, *, *, allow",
                "p, role:system-admin, gpgkeys, *, *, allow",
                "p, role:system-admin, accounts, get, *, allow",
                "p, role:system-admin, accounts, update, *, allow",
                "",
                "# ============================================",
                "# Cluster Admin Role",
                "# ============================================",
                "# Break-glass full access",
                "p, role:cluster-admin, *, *, *, allow",
                "",
                "# ============================================",
                "# Role Assignments (Generated from User CRDs)",
                "# ============================================",
            ])

            # Add user role assignments (dynamic from User CRDs)
            # ArgoCD roles are hierarchical - assign only the highest role per user
            role_hierarchy = ['cluster-admin', 'system-admin', 'platform-operator', 'app-developer']

            for user in users:
                spec = user.get('spec', {})
                email = spec.get('email')
                roles = spec.get('roles', [])
                enabled = spec.get('enabled', True)

                if not enabled or not email:
                    continue

                # Find the highest role in the hierarchy
                highest_role = None
                for role in role_hierarchy:
                    if role in roles:
                        highest_role = role
                        break

                # Assign only the highest role for ArgoCD
                if highest_role:
                    policy_lines.append(f"g, {email}, role:{highest_role}")

            policy_csv = '\n'.join(policy_lines) + '\n'

            # Check if ConfigMap exists
            cm_name = 'argocd-rbac-cm'
            try:
                existing_cm = self.v1.read_namespaced_config_map(name=cm_name, namespace='argocd')

                # Update existing ConfigMap
                if existing_cm.data is None:
                    existing_cm.data = {}

                existing_cm.data['policy.csv'] = policy_csv
                existing_cm.data['policy.default'] = 'role:readonly'
                existing_cm.data['scopes'] = '[groups, email]'

                self.v1.replace_namespaced_config_map(
                    name=cm_name,
                    namespace='argocd',
                    body=existing_cm
                )
                print(f"Updated ArgoCD RBAC ConfigMap with {len(users)} users", flush=True)

            except client.rest.ApiException as e:
                if e.status == 404:
                    # Create new ConfigMap
                    cm = client.V1ConfigMap(
                        metadata=client.V1ObjectMeta(
                            name=cm_name,
                            namespace='argocd',
                            labels={
                                'app.kubernetes.io/managed-by': 'rbac-operator',
                                'app.kubernetes.io/part-of': 'argocd'
                            }
                        ),
                        data={
                            'policy.csv': policy_csv,
                            'policy.default': 'role:readonly',
                            'scopes': '[groups, email]'
                        }
                    )

                    self.v1.create_namespaced_config_map(
                        namespace='argocd',
                        body=cm
                    )
                    print(f"Created ArgoCD RBAC ConfigMap with {len(users)} users", flush=True)
                else:
                    raise

        except Exception as e:
            print(f"ERROR syncing ArgoCD RBAC: {e}", file=sys.stderr, flush=True)
            import traceback
            traceback.print_exc()


def watch_requests(service: RBACOperatorService, shared_dir='/shared'):
    """Watch for request files and process them"""
    global shutdown_requested

    print(f'RBAC Operator service watching {shared_dir}', flush=True)

    processed = set()
    last_reconcile = 0
    reconcile_interval = 300  # Reconcile every 5 minutes

    while not shutdown_requested:
        try:
            # Periodic full reconciliation
            current_time = time.time()
            if current_time - last_reconcile > reconcile_interval:
                service.reconcile_all()
                last_reconcile = current_time

            # Check for request files
            if not os.path.exists(shared_dir):
                print(f"Shared directory {shared_dir} does not exist, waiting...", file=sys.stderr, flush=True)
                time.sleep(1)
                continue

            files = os.listdir(shared_dir)
            request_files = [f for f in files if f.startswith('request-') and f.endswith('.json')]

            for req_file in request_files:
                if shutdown_requested:
                    print("[shutdown] Stopping request processing...", flush=True)
                    break

                if req_file in processed:
                    continue

                req_path = os.path.join(shared_dir, req_file)
                request_id = req_file.replace('request-', '').replace('.json', '')
                resp_path = os.path.join(shared_dir, f'response-{request_id}.txt')

                try:
                    # Read request
                    with open(req_path, 'r') as f:
                        binding_context = f.read()

                    print(f"[handler] Processing request from {req_file}", flush=True)

                    # Process the event
                    try:
                        context_data = json.loads(binding_context)

                        # Trigger full reconciliation on any event
                        service.reconcile_all()

                        response = "OK"
                        print(f"[handler] Successfully processed event", flush=True)
                    except Exception as e:
                        response = f"ERROR: {e}"
                        print(f"ERROR processing request: {e}", file=sys.stderr, flush=True)
                        import traceback
                        traceback.print_exc()

                    # Write response
                    with open(resp_path, 'w') as f:
                        f.write(response)

                    print(f"[handler] Wrote response to {os.path.basename(resp_path)}", flush=True)
                    processed.add(req_file)

                except Exception as e:
                    print(f"ERROR handling {req_file}: {e}", file=sys.stderr)
                    # Write error response
                    try:
                        with open(resp_path, 'w') as f:
                            f.write(f"ERROR: {e}")
                    except:
                        pass

            # Clean up old processed files
            current_time = time.time()
            for filename in list(processed):
                # Remove from processed set if file no longer exists
                if not os.path.exists(os.path.join(shared_dir, filename)):
                    processed.discard(filename)

            # Small delay to avoid busy loop
            time.sleep(1)

        except KeyboardInterrupt:
            print("\n[shutdown] Keyboard interrupt received", flush=True)
            break
        except Exception as e:
            if not shutdown_requested:
                print(f"ERROR in watch loop: {e}", file=sys.stderr, flush=True)
                time.sleep(1)
            else:
                break

    print("[shutdown] Service stopped cleanly", flush=True)


if __name__ == '__main__':
    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Initialize service
    service = RBACOperatorService()

    # Start watching for request files
    shared_dir = '/shared'

    try:
        watch_requests(service, shared_dir)
    except Exception as e:
        print(f"FATAL ERROR: {e}", file=sys.stderr, flush=True)
        import traceback
        traceback.print_exc()
        sys.exit(1)

    sys.exit(0)
