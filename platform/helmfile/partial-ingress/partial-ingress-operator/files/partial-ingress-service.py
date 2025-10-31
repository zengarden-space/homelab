#!/usr/bin/env python3
"""
PartialIngress Operator Service
Handles PartialIngress and CompositeIngressHost CRDs to enable partial environment deployments
"""

import os
import sys
import json
import time
import signal
import hashlib
import fnmatch
from datetime import datetime
from kubernetes import client, config
from kubernetes.client.rest import ApiException


# Global flag for graceful shutdown
shutdown_requested = False


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    global shutdown_requested
    print(f"\n[shutdown] Received signal {signum}, initiating graceful shutdown...", flush=True)
    shutdown_requested = True


class PartialIngressService:
    """Main service for processing PartialIngress and CompositeIngressHost events"""

    def __init__(self):
        # Load Kubernetes config from service account
        config.load_incluster_config()
        self.v1 = client.CoreV1Api()
        self.networking_v1 = client.NetworkingV1Api()
        self.custom_api = client.CustomObjectsApi()

        print('PartialIngress Operator service initialized', flush=True)

    def compute_hash(self, hostname, ingress_class_name):
        """Compute hash for naming replicated resources"""
        hash_input = f"{hostname}:{ingress_class_name}"
        return hashlib.sha256(hash_input.encode()).hexdigest()[:8]

    def get_all_composite_ingress_hosts(self):
        """Get all CompositeIngressHost resources across all namespaces"""
        try:
            result = self.custom_api.list_cluster_custom_object(
                group='networking.zengarden.space',
                version='v1',
                plural='compositeingresshosts'
            )
            return result.get('items', [])
        except ApiException as e:
            if e.status == 404:
                return []
            print(f"ERROR: Failed to list CompositeIngressHosts: {e}", file=sys.stderr)
            raise

    def deduplicate_composite_hosts(self, composite_hosts):
        """Deduplicate CompositeIngressHost resources by spec"""
        seen = {}
        for host in composite_hosts:
            spec = host.get('spec', {})
            key = (spec.get('baseHost'), spec.get('hostPattern'), spec.get('ingressClassName'))
            if key not in seen:
                seen[key] = host
        return list(seen.values())

    def find_base_ingresses(self, base_host, ingress_class_name, namespace):
        """Find all Ingress resources matching baseHost and ingressClassName in a specific namespace"""
        try:
            namespace_ingresses = self.networking_v1.list_namespaced_ingress(namespace=namespace)
            matching = []

            for ing in namespace_ingresses.items:
                # Check ingressClassName
                if ing.spec.ingress_class_name != ingress_class_name:
                    continue

                # Check if any rule matches baseHost
                if ing.spec.rules:
                    for rule in ing.spec.rules:
                        if rule.host == base_host:
                            matching.append(ing)
                            break

            return matching
        except ApiException as e:
            print(f"ERROR: Failed to list Ingresses in namespace {namespace}: {e}", file=sys.stderr)
            raise

    def find_matching_partial_ingresses(self, host_pattern):
        """Find all PartialIngress resources matching the hostPattern"""
        try:
            result = self.custom_api.list_cluster_custom_object(
                group='networking.zengarden.space',
                version='v1',
                plural='partialingresses'
            )

            matching = []
            for ping in result.get('items', []):
                spec = ping.get('spec', {})
                rules = spec.get('rules', [])

                for rule in rules:
                    host = rule.get('host', '')
                    if fnmatch.fnmatch(host, host_pattern):
                        matching.append(ping)
                        break

            return matching
        except ApiException as e:
            if e.status == 404:
                return []
            print(f"ERROR: Failed to list PartialIngresses: {e}", file=sys.stderr)
            raise

    def extract_paths_from_ingress(self, ingress):
        """Extract paths and backends from an Ingress"""
        paths = []
        if ingress.spec.rules:
            for rule in ingress.spec.rules:
                if rule.http and rule.http.paths:
                    for path_obj in rule.http.paths:
                        paths.append({
                            'path': path_obj.path,
                            'pathType': path_obj.path_type,
                            'backend': path_obj.backend
                        })
        return paths

    def extract_paths_from_partial_ingress(self, partial_ingress):
        """Extract paths from a PartialIngress spec"""
        paths = []
        spec = partial_ingress.get('spec', {})
        rules = spec.get('rules', [])

        for rule in rules:
            http = rule.get('http', {})
            paths_list = http.get('paths', [])

            for path_obj in paths_list:
                paths.append(path_obj.get('path', '/'))

        return paths

    def is_path_overridden(self, path, overridden_paths):
        """Check if a path is overridden by PartialIngress"""
        # Simple string comparison for now
        # TODO: Handle more complex path matching (Prefix vs Exact)
        return path in overridden_paths

    def build_path_override_map(self, hostname, ingress_class_name):
        """
        Build a set of all paths provided by ALL PartialIngresses for a specific hostname.
        Returns a set of path strings.
        """
        try:
            all_partial_ingresses = self.custom_api.list_cluster_custom_object(
                group='networking.zengarden.space',
                version='v1',
                plural='partialingresses'
            ).get('items', [])

            overridden_paths = set()

            for pi in all_partial_ingresses:
                # Skip if being deleted
                if pi.get('metadata', {}).get('deletionTimestamp'):
                    continue

                pi_spec = pi.get('spec', {})
                pi_class = pi_spec.get('ingressClassName')

                # Only consider PartialIngresses with matching hostname and ingressClassName
                if pi_class != ingress_class_name:
                    continue

                pi_rules = pi_spec.get('rules', [])
                for rule in pi_rules:
                    pi_hostname = rule.get('host', '')
                    # Exact hostname match
                    if pi_hostname == hostname:
                        # Extract all paths from this PartialIngress
                        http = rule.get('http', {})
                        paths_list = http.get('paths', [])
                        for path_obj in paths_list:
                            path = path_obj.get('path', '/')
                            overridden_paths.add(path)
                        break

            return overridden_paths

        except ApiException as e:
            if e.status == 404:
                return set()
            print(f"ERROR: Failed to build path override map: {e}", file=sys.stderr)
            raise

    def process_partial_ingress(self, binding_context):
        """Process a PartialIngress event from binding context"""
        try:
            context_data = json.loads(binding_context)

            if not context_data or len(context_data) == 0:
                raise Exception("Empty binding context")

            binding = context_data[0]

            # Handle both single object and multiple objects
            objects = []
            if 'object' in binding:
                objects = [{'object': binding['object']}]
            elif 'objects' in binding:
                objects = binding['objects']

            if not objects:
                print("WARNING: No objects in binding context", file=sys.stderr)
                return

            # Process each PartialIngress
            for obj_wrapper in objects:
                obj = obj_wrapper.get('object', {})
                self._process_single_partial_ingress(obj)

        except Exception as e:
            print(f"ERROR in process_partial_ingress: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            raise

    def _process_single_partial_ingress(self, obj):
        """Process a single PartialIngress object"""
        metadata = obj.get('metadata', {})
        spec = obj.get('spec', {})

        namespace = metadata.get('namespace')
        name = metadata.get('name')
        uid = metadata.get('uid')
        deletion_timestamp = metadata.get('deletionTimestamp')

        print(f"Processing PartialIngress: {namespace}/{name}", flush=True)

        # Handle deletion - check if we need to cleanup orphaned replicated Ingresses
        if deletion_timestamp:
            print(f"  PartialIngress is being deleted, checking for orphaned replicated Ingresses", flush=True)
            self._cleanup_orphaned_replicated_ingresses()
            return

        # Extract hostname from PartialIngress
        rules = spec.get('rules', [])
        if not rules:
            print("WARNING: No rules in PartialIngress, skipping", flush=True)
            return

        hostname = rules[0].get('host', '')
        if not hostname:
            print("WARNING: No host in PartialIngress rules, skipping", flush=True)
            return

        ingress_class_name = spec.get('ingressClassName', '')

        print(f"  Hostname: {hostname}", flush=True)
        print(f"  IngressClass: {ingress_class_name}", flush=True)

        # 1. Generate Ingress from PartialIngress in the same namespace (owned by PartialIngress)
        self._generate_ingress_from_partial(obj)

        # 2. Find matching CompositeIngressHosts (process ALL, no deduplication)
        all_composite_hosts = self.get_all_composite_ingress_hosts()

        replicated_ingresses = []

        for composite_host in all_composite_hosts:
            cih_spec = composite_host.get('spec', {})
            cih_metadata = composite_host.get('metadata', {})
            base_host = cih_spec.get('baseHost')
            host_pattern = cih_spec.get('hostPattern')
            cih_ingress_class = cih_spec.get('ingressClassName')

            # Check if this PartialIngress matches the pattern
            if not fnmatch.fnmatch(hostname, host_pattern):
                continue

            if cih_ingress_class != ingress_class_name:
                continue

            print(f"  Matched CompositeIngressHost: baseHost={base_host}, pattern={host_pattern}", flush=True)

            # Find base Ingresses in the same namespace as CompositeIngressHost
            cih_namespace = cih_metadata.get('namespace')
            base_ingresses = self.find_base_ingresses(base_host, cih_ingress_class, cih_namespace)
            print(f"  Found {len(base_ingresses)} base Ingresses in {cih_namespace}", flush=True)

            # Build path override map for this hostname from ALL PartialIngresses
            all_overridden_paths = self.build_path_override_map(hostname, ingress_class_name)
            print(f"  Paths provided by ALL PartialIngresses for {hostname}: {all_overridden_paths}", flush=True)

            # Replicate non-overridden Ingresses (owned by CompositeIngressHost)
            for base_ing in base_ingresses:
                base_paths = self.extract_paths_from_ingress(base_ing)

                # Check if any paths are NOT overridden by ANY PartialIngress for this hostname
                non_overridden_paths = [
                    p for p in base_paths
                    if not self.is_path_overridden(p['path'], all_overridden_paths)
                ]

                if non_overridden_paths:
                    replicated_ing = self._replicate_ingress(
                        base_ing,
                        hostname,
                        ingress_class_name,
                        non_overridden_paths,
                        obj,
                        composite_host
                    )
                    if replicated_ing:
                        replicated_ingresses.append({
                            'name': replicated_ing.metadata.name,
                            'namespace': replicated_ing.metadata.namespace,
                            'sourceIngress': f"{base_ing.metadata.namespace}/{base_ing.metadata.name}"
                        })

        # Update PartialIngress status
        self._update_partial_ingress_status(namespace, name, replicated_ingresses)

        print(f"✓ Successfully processed PartialIngress: {namespace}/{name}", flush=True)

    def _generate_ingress_from_partial(self, partial_ingress_obj):
        """Generate standard Ingress from PartialIngress in the same namespace"""
        metadata = partial_ingress_obj.get('metadata', {})
        spec = partial_ingress_obj.get('spec', {})

        namespace = metadata.get('namespace')
        name = metadata.get('name')
        uid = metadata.get('uid')

        # Create Ingress with same spec as PartialIngress
        ingress = client.V1Ingress(
            api_version='networking.k8s.io/v1',
            kind='Ingress',
            metadata=client.V1ObjectMeta(
                name=name,
                namespace=namespace,
                labels={
                    'app.kubernetes.io/managed-by': 'partial-ingress-operator',
                    'partial-ingress.zengarden.space/source': name
                },
                annotations=spec.get('annotations', {}),
                owner_references=[
                    client.V1OwnerReference(
                        api_version='networking.zengarden.space/v1',
                        kind='PartialIngress',
                        name=name,
                        uid=uid,
                        controller=True,
                        block_owner_deletion=True
                    )
                ]
            ),
            spec=self._dict_to_ingress_spec(spec)
        )

        try:
            self.networking_v1.read_namespaced_ingress(name=name, namespace=namespace)
            # Update if exists
            self.networking_v1.replace_namespaced_ingress(
                name=name,
                namespace=namespace,
                body=ingress
            )
            print(f"  Updated Ingress: {namespace}/{name}", flush=True)
        except ApiException as e:
            if e.status == 404:
                # Create if doesn't exist
                self.networking_v1.create_namespaced_ingress(
                    namespace=namespace,
                    body=ingress
                )
                print(f"  Created Ingress: {namespace}/{name}", flush=True)
            else:
                raise

    def _replicate_ingress(self, base_ingress, new_hostname, ingress_class_name, paths, partial_ingress_obj, composite_host_obj):
        """
        Replicate an Ingress to CompositeIngressHost namespace with new hostname.
        The replicated Ingress points to LOCAL services in the CIH namespace.
        """
        # Compute hash for naming
        resource_hash = self.compute_hash(new_hostname, ingress_class_name)

        base_namespace = base_ingress.metadata.namespace
        base_name = base_ingress.metadata.name

        new_name = f"{base_name}-{resource_hash}"

        pi_metadata = partial_ingress_obj.get('metadata', {})
        pi_namespace = pi_metadata.get('namespace')
        pi_name = pi_metadata.get('name')

        # Get CompositeIngressHost metadata for owner reference
        cih_metadata = composite_host_obj.get('metadata', {})
        cih_namespace = cih_metadata.get('namespace')
        cih_name = cih_metadata.get('name')
        cih_uid = cih_metadata.get('uid')

        # Build HTTP paths - use SAME backend (local service) as base Ingress
        http_paths = []
        for path_info in paths:
            http_paths.append(
                client.V1HTTPIngressPath(
                    path=path_info['path'],
                    path_type=path_info['pathType'],
                    backend=path_info['backend']  # Points to local service in CIH namespace
                )
            )

        # Build rules with new hostname (from PartialIngress)
        rules = [
            client.V1IngressRule(
                host=new_hostname,
                http=client.V1HTTPIngressRuleValue(
                    paths=http_paths
                )
            )
        ]

        # Copy and modify annotations
        annotations = dict(base_ingress.metadata.annotations or {})
        annotations['partial-ingress.zengarden.space/replicated-for'] = new_hostname
        annotations['partial-ingress.zengarden.space/source-partial-ingress'] = f"{pi_namespace}/{pi_name}"

        # Handle TLS
        tls = []
        if base_ingress.spec.tls:
            for tls_config in base_ingress.spec.tls:
                # Append hash to secret name
                original_secret_name = tls_config.secret_name
                new_secret_name = f"{original_secret_name}-{resource_hash}" if original_secret_name else None

                tls.append(
                    client.V1IngressTLS(
                        hosts=[new_hostname],
                        secret_name=new_secret_name
                    )
                )

        # Build owner reference - owned by CompositeIngressHost
        owner_references = [
            client.V1OwnerReference(
                api_version='networking.zengarden.space/v1',
                kind='CompositeIngressHost',
                name=cih_name,
                uid=cih_uid,
                controller=True,
                block_owner_deletion=True
            )
        ]
        print(f"  Setting CompositeIngressHost {cih_namespace}/{cih_name} as owner", flush=True)

        # Create replicated Ingress in CIH namespace (base namespace)
        ingress = client.V1Ingress(
            api_version='networking.k8s.io/v1',
            kind='Ingress',
            metadata=client.V1ObjectMeta(
                name=new_name,
                namespace=cih_namespace,  # Deploy in CompositeIngressHost namespace!
                labels={
                    'app.kubernetes.io/managed-by': 'partial-ingress-operator',
                    'partial-ingress.zengarden.space/replicated': 'true',
                    'partial-ingress.zengarden.space/hostname': new_hostname
                },
                annotations=annotations,
                owner_references=owner_references
            ),
            spec=client.V1IngressSpec(
                ingress_class_name=ingress_class_name,
                rules=rules,
                tls=tls if tls else None
            )
        )

        try:
            self.networking_v1.read_namespaced_ingress(name=new_name, namespace=cih_namespace)
            # Update if exists
            result = self.networking_v1.replace_namespaced_ingress(
                name=new_name,
                namespace=cih_namespace,
                body=ingress
            )
            print(f"  Updated replicated Ingress: {cih_namespace}/{new_name}", flush=True)
            return result
        except ApiException as e:
            if e.status == 404:
                # Create if doesn't exist
                result = self.networking_v1.create_namespaced_ingress(
                    namespace=cih_namespace,
                    body=ingress
                )
                print(f"  Created replicated Ingress: {cih_namespace}/{new_name}", flush=True)
                return result
            else:
                raise

    def _dict_to_ingress_spec(self, spec_dict):
        """Convert dictionary to V1IngressSpec"""
        # This is a simplified conversion - you may need to handle more cases
        return client.V1IngressSpec(
            ingress_class_name=spec_dict.get('ingressClassName'),
            default_backend=spec_dict.get('defaultBackend'),
            rules=spec_dict.get('rules'),
            tls=spec_dict.get('tls')
        )

    def _cleanup_orphaned_replicated_ingresses(self):
        """
        Cleanup replicated Ingresses when the last PartialIngress for a hostname pattern is deleted.
        Replicated Ingresses are owned by CompositeIngressHost, so we need manual cleanup.
        """
        print(f"  Checking for orphaned replicated Ingresses", flush=True)

        try:
            # Get all CompositeIngressHosts
            all_composite_hosts = self.get_all_composite_ingress_hosts()

            # Get all active PartialIngresses
            all_partial_ingresses = self.custom_api.list_cluster_custom_object(
                group='networking.zengarden.space',
                version='v1',
                plural='partialingresses'
            ).get('items', [])

            # For each CompositeIngressHost, check if there are matching PartialIngresses
            for cih in all_composite_hosts:
                cih_metadata = cih.get('metadata', {})
                cih_spec = cih.get('spec', {})
                cih_namespace = cih_metadata.get('namespace')
                cih_name = cih_metadata.get('name')

                host_pattern = cih_spec.get('hostPattern')
                ingress_class = cih_spec.get('ingressClassName')

                # Find matching PartialIngresses (excluding ones being deleted)
                matching_pis = []
                for pi in all_partial_ingresses:
                    # Skip if being deleted
                    if pi.get('metadata', {}).get('deletionTimestamp'):
                        continue

                    pi_spec = pi.get('spec', {})
                    pi_class = pi_spec.get('ingressClassName')

                    if pi_class != ingress_class:
                        continue

                    # Check if hostname matches pattern
                    pi_rules = pi_spec.get('rules', [])
                    for rule in pi_rules:
                        hostname = rule.get('host', '')
                        if hostname and fnmatch.fnmatch(hostname, host_pattern):
                            matching_pis.append(pi)
                            break

                # If no matching PartialIngresses, delete all replicated Ingresses for this CIH
                if len(matching_pis) == 0:
                    print(f"  No active PartialIngresses for CIH {cih_namespace}/{cih_name}, cleaning up replicated Ingresses", flush=True)
                    self._delete_replicated_ingresses_for_cih(cih_namespace, cih_name)
                else:
                    print(f"  CIH {cih_namespace}/{cih_name} still has {len(matching_pis)} matching PartialIngress(es)", flush=True)

        except Exception as e:
            print(f"ERROR: Failed to cleanup orphaned replicated Ingresses: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()

    def _delete_replicated_ingresses_for_cih(self, cih_namespace, cih_name):
        """Delete all replicated Ingresses in a CompositeIngressHost namespace"""
        try:
            # Find all replicated Ingresses in the CIH namespace
            all_ingresses = self.networking_v1.list_namespaced_ingress(
                namespace=cih_namespace,
                label_selector='partial-ingress.zengarden.space/replicated=true'
            )

            deleted_count = 0
            for ing in all_ingresses.items:
                # Verify it's owned by this CIH
                owner_refs = ing.metadata.owner_references or []
                is_owned_by_cih = False
                for owner in owner_refs:
                    if owner.kind == 'CompositeIngressHost' and owner.name == cih_name:
                        is_owned_by_cih = True
                        break

                if is_owned_by_cih:
                    print(f"    Deleting replicated Ingress: {cih_namespace}/{ing.metadata.name}", flush=True)
                    try:
                        self.networking_v1.delete_namespaced_ingress(
                            name=ing.metadata.name,
                            namespace=cih_namespace
                        )
                        deleted_count += 1
                    except ApiException as e:
                        if e.status != 404:
                            print(f"WARNING: Failed to delete Ingress {ing.metadata.name}: {e}", file=sys.stderr)

            if deleted_count > 0:
                print(f"  Deleted {deleted_count} replicated Ingress(es) for CIH {cih_namespace}/{cih_name}", flush=True)

        except Exception as e:
            print(f"ERROR: Failed to delete replicated Ingresses: {e}", file=sys.stderr)

    def _update_partial_ingress_status(self, namespace, name, replicated_ingresses):
        """Update PartialIngress status"""
        timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

        status = {
            'status': {
                'generatedIngress': name,
                'replicatedIngresses': replicated_ingresses,
                'lastUpdated': timestamp
            }
        }

        try:
            self.custom_api.patch_namespaced_custom_object_status(
                group='networking.zengarden.space',
                version='v1',
                namespace=namespace,
                plural='partialingresses',
                name=name,
                body=status
            )
            print(f"  Updated status for PartialIngress: {namespace}/{name}", flush=True)
        except Exception as e:
            print(f"WARNING: Failed to update status: {e}", file=sys.stderr)

    def process_composite_ingress_host(self, binding_context):
        """Process a CompositeIngressHost event"""
        try:
            context_data = json.loads(binding_context)

            if not context_data or len(context_data) == 0:
                raise Exception("Empty binding context")

            binding = context_data[0]

            # Handle both single object and multiple objects
            objects = []
            if 'object' in binding:
                objects = [{'object': binding['object']}]
            elif 'objects' in binding:
                objects = binding['objects']

            if not objects:
                print("WARNING: No objects in binding context", file=sys.stderr)
                return

            # Process each CompositeIngressHost
            for obj_wrapper in objects:
                obj = obj_wrapper.get('object', {})
                self._process_single_composite_ingress_host(obj)

        except Exception as e:
            print(f"ERROR in process_composite_ingress_host: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            raise

    def _process_single_composite_ingress_host(self, obj):
        """Process a single CompositeIngressHost object"""
        metadata = obj.get('metadata', {})
        spec = obj.get('spec', {})

        namespace = metadata.get('namespace')
        name = metadata.get('name')

        base_host = spec.get('baseHost')
        ingress_class_name = spec.get('ingressClassName')

        print(f"Processing CompositeIngressHost: {namespace}/{name}", flush=True)
        print(f"  BaseHost: {base_host}", flush=True)

        # Scan for base Ingresses in the same namespace
        base_ingresses = self.find_base_ingresses(base_host, ingress_class_name, namespace)

        print(f"  Discovered {len(base_ingresses)} Ingresses in {namespace}", flush=True)

        # Update status
        self._update_composite_host_status(namespace, name, len(base_ingresses))

        print(f"✓ Successfully processed CompositeIngressHost: {namespace}/{name}", flush=True)

    def _update_composite_host_status(self, namespace, name, discovered_count):
        """Update CompositeIngressHost status"""
        timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

        status = {
            'status': {
                'discoveredIngresses': discovered_count,
                'lastScanned': timestamp
            }
        }

        try:
            self.custom_api.patch_namespaced_custom_object_status(
                group='networking.zengarden.space',
                version='v1',
                namespace=namespace,
                plural='compositeingresshosts',
                name=name,
                body=status
            )
            print(f"  Updated status for CompositeIngressHost: {namespace}/{name}", flush=True)
        except Exception as e:
            print(f"WARNING: Failed to update status: {e}", file=sys.stderr)


def watch_requests(service, shared_dir='/shared'):
    """Watch for request files and process them"""
    global shutdown_requested

    print(f'PartialIngress Operator service watching {shared_dir}', flush=True)

    processed = set()

    while not shutdown_requested:
        try:
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

                    # Determine which handler to call based on context
                    # We'll use a simple approach: check the first object's kind
                    try:
                        context_data = json.loads(binding_context)
                        if context_data and len(context_data) > 0:
                            binding = context_data[0]

                            # Safely extract the object
                            obj = None
                            if 'object' in binding:
                                obj = binding['object']
                            elif 'objects' in binding and len(binding['objects']) > 0:
                                obj = binding['objects'][0].get('object', {})

                            if not obj:
                                print(f"WARNING: No object found in binding context", file=sys.stderr)
                                response = "OK"
                                continue

                            kind = obj.get('kind', '')

                            if kind == 'PartialIngress':
                                service.process_partial_ingress(binding_context)
                            elif kind == 'CompositeIngressHost':
                                service.process_composite_ingress_host(binding_context)
                            else:
                                print(f"WARNING: Unknown kind: {kind}", file=sys.stderr)

                        response = "OK"
                        print(f"[handler] Successfully processed request", flush=True)
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
                    try:
                        with open(resp_path, 'w') as f:
                            f.write(f"ERROR: {e}")
                    except:
                        pass

            # Clean up old processed files
            current_time = time.time()
            for filename in list(processed):
                if not os.path.exists(os.path.join(shared_dir, filename)):
                    processed.discard(filename)

            time.sleep(0.1)

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
    # Register signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Initialize service
    service = PartialIngressService()

    # Start watching
    shared_dir = '/shared'

    try:
        watch_requests(service, shared_dir)
    except Exception as e:
        print(f"FATAL ERROR: {e}", file=sys.stderr, flush=True)
        import traceback
        traceback.print_exc()
        sys.exit(1)

    sys.exit(0)
