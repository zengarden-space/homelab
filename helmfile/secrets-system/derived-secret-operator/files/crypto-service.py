#!/usr/bin/env python3
"""
Derived Secret Operator Service
Handles DerivedSecret CRD events and derives secrets using Argon2id
"""

import os
import sys
import json
import base64
import time
import signal
import argon2
import hashlib
from datetime import datetime
from kubernetes import client, config


# Global flag for graceful shutdown
shutdown_requested = False


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    global shutdown_requested
    print(f"\n[shutdown] Received signal {signum}, initiating graceful shutdown...", flush=True)
    shutdown_requested = True


class DerivedSecretService:
    """Main service for processing DerivedSecret events"""
    
    def __init__(self):
        # Load Kubernetes config from service account
        config.load_incluster_config()
        self.v1 = client.CoreV1Api()
        self.custom_api = client.CustomObjectsApi()
        
        # Load master password
        self.master_password = self._load_master_password()
        
        # Argon2 parameters from environment variables
        self.time_cost = int(os.getenv('ARGON2_TIME_COST', '3'))
        self.memory_cost = int(os.getenv('ARGON2_MEMORY_COST', '65536'))
        self.parallelism = int(os.getenv('ARGON2_PARALLELISM', '4'))
        
        print(f'Argon2 config: time={self.time_cost}, memory={self.memory_cost}KB, parallelism={self.parallelism}')
    
    def _load_master_password(self):
        """Load master password from mounted secret"""
        password_path = '/master-password/master-password'
        try:
            with open(password_path, 'r') as f:
                return f.read().strip()
        except Exception as e:
            print(f"ERROR: Failed to load master password: {e}", file=sys.stderr)
            sys.exit(1)
    
    def derive_secret(self, identifier, context, length):
        """Derive a secret using Argon2id KDF"""
        # Create deterministic salt from context and identifier
        salt_input = f"{context}:{identifier}"
        salt = hashlib.sha256(salt_input.encode()).digest()
        
        # Derive using Argon2id
        raw = argon2.low_level.hash_secret_raw(
            secret=self.master_password.encode(),
            salt=salt,
            time_cost=self.time_cost,
            memory_cost=self.memory_cost,
            parallelism=self.parallelism,
            hash_len=max(64, length * 2),  # Ensure enough entropy
            type=argon2.low_level.Type.ID
        )
        
        return self._to_base62(raw, length)
    
    def _to_base62(self, data, length):
        """Convert bytes to base62 (A-Za-z0-9) string"""
        alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        num = int.from_bytes(data, 'big')
        
        if num == 0:
            return alphabet[0] * length
        
        result = []
        while num and len(result) < length:
            num, remainder = divmod(num, 62)
            result.append(alphabet[remainder])
        
        # Pad if needed
        while len(result) < length:
            result.append(alphabet[0])
        
        return ''.join(reversed(result))[:length]
    
    def process_derived_secret(self, binding_context):
        """Process a DerivedSecret event from binding context"""
        try:
            # Parse binding context
            context_data = json.loads(binding_context)
            
            # Extract the object from first binding
            if not context_data or len(context_data) == 0:
                raise Exception("Empty binding context")
            
            binding = context_data[0]
            
            # Shell-operator can send objects in two ways:
            # 1. Single event: binding['object'] for Modified/Added/Deleted events
            # 2. Synchronization: binding['objects'] array for initial sync
            objects = []

            if 'object' in binding:
                # Single object event (Modified, Added, Deleted)
                objects = [{'object': binding['object']}]
            elif 'objects' in binding:
                # Multiple objects from synchronization
                objects = binding['objects']

            if not objects:
                print("WARNING: No objects in binding context", file=sys.stderr)
                print("---")
                print(binding_context)
                print("---")
                return
            
            # Process each object (there may be multiple DerivedSecrets)
            for obj_wrapper in objects:
                obj = obj_wrapper.get('object', {})
                self._process_single_derived_secret(obj)
                
        except Exception as e:
            print(f"ERROR in process_derived_secret: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            raise
    
    def _process_single_derived_secret(self, obj):
        """Process a single DerivedSecret object"""
        metadata = obj.get('metadata', {})
        spec = obj.get('spec', {})
        
        namespace = metadata.get('namespace')
        name = metadata.get('name')
        uid = metadata.get('uid')
        
        print(f"Processing DerivedSecret: {namespace}/{name}", flush=True)
        
        # Derive secrets for each field in spec
        secret_data = {}
        identifier = f"{namespace}/{name}"
        
        for field_name, length in spec.items():
            if not isinstance(length, int):
                print(f"WARNING: Skipping {field_name}, length must be integer", file=sys.stderr, flush=True)
                continue
            
            print(f"Deriving {field_name} ({length} chars)...", flush=True)
            secret_value = self.derive_secret(identifier, field_name, length)
            
            # Base64 encode for Kubernetes Secret
            encoded_value = base64.b64encode(secret_value.encode()).decode()
            secret_data[field_name] = encoded_value
        
        if not secret_data:
            print("WARNING: No secrets derived, skipping Secret creation", flush=True)
            return
        
        # Create or update Kubernetes Secret
        secret_name = name
        self._create_or_update_secret(
            namespace=namespace,
            name=secret_name,
            data=secret_data,
            owner_name=name,
            owner_uid=uid
        )
        
        # Update DerivedSecret status
        self._update_status(namespace, name, secret_name)
        
        print(f"✓ Successfully processed DerivedSecret: {namespace}/{name}", flush=True)
        print(f"  Generated Secret: {namespace}/{secret_name}", flush=True)
    
    def _create_or_update_secret(self, namespace, name, data, owner_name, owner_uid):
        """Create or update a Kubernetes Secret, preserving unmanaged keys"""
        try:
            # Try to read existing secret
            existing_secret = self.v1.read_namespaced_secret(name=name, namespace=namespace)
            
            # Preserve existing keys that are not in the new data
            existing_data = existing_secret.data or {}
            merged_data = existing_data.copy()
            
            # Override only the keys specified in DerivedSecret
            merged_data.update(data)
            
            print(f"Merging secret data: {len(existing_data)} existing keys, {len(data)} derived keys, {len(merged_data)} total", flush=True)
            
            # Update the secret with merged data
            secret = client.V1Secret(
                api_version='v1',
                kind='Secret',
                metadata=client.V1ObjectMeta(
                    name=name,
                    namespace=namespace,
                    labels={
                        'app.kubernetes.io/managed-by': 'derived-secret-operator',
                        'zengarden.space/derived-from': owner_name
                    },
                    owner_references=[
                        client.V1OwnerReference(
                            api_version='zengarden.space/v1',
                            kind='DerivedSecret',
                            name=owner_name,
                            uid=owner_uid,
                            controller=True,
                            block_owner_deletion=True
                        )
                    ]
                ),
                type='Opaque',
                data=merged_data
            )
            
            self.v1.replace_namespaced_secret(
                name=name,
                namespace=namespace,
                body=secret
            )
            print(f"Updated Secret: {namespace}/{name} (preserved {len(existing_data) - len(data)} unmanaged keys)", flush=True)
            
        except client.rest.ApiException as e:
            if e.status == 404:
                # Secret doesn't exist, create it
                secret = client.V1Secret(
                    api_version='v1',
                    kind='Secret',
                    metadata=client.V1ObjectMeta(
                        name=name,
                        namespace=namespace,
                        labels={
                            'app.kubernetes.io/managed-by': 'derived-secret-operator',
                            'zengarden.space/derived-from': owner_name
                        },
                        owner_references=[
                            client.V1OwnerReference(
                                api_version='zengarden.space/v1',
                                kind='DerivedSecret',
                                name=owner_name,
                                uid=owner_uid,
                                controller=True,
                                block_owner_deletion=True
                            )
                        ]
                    ),
                    type='Opaque',
                    data=data
                )
                
                self.v1.create_namespaced_secret(
                    namespace=namespace,
                    body=secret
                )
                print(f"Created Secret: {namespace}/{name}", flush=True)
            else:
                raise
    
    def _update_status(self, namespace, name, secret_name):
        """Update DerivedSecret status"""
        timestamp = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
        
        status = {
            'status': {
                'secretName': secret_name,
                'lastUpdated': timestamp
            }
        }
        
        try:
            self.custom_api.patch_namespaced_custom_object_status(
                group='zengarden.space',
                version='v1',
                namespace=namespace,
                plural='derivedsecrets',
                name=name,
                body=status
            )
            print(f"Updated status for DerivedSecret: {namespace}/{name}")
        except Exception as e:
            print(f"WARNING: Failed to update status: {e}", file=sys.stderr)


def watch_requests(service, shared_dir='/shared'):
    """Watch for request files and process them"""
    global shutdown_requested
    
    print(f'Derived Secret Operator service watching {shared_dir}', flush=True)
    
    processed = set()
    
    while not shutdown_requested:
        try:
            # List all request files
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
                    print(f"[handler] Binding context length: {len(binding_context)} bytes", flush=True)
                    
                    # Process the DerivedSecret
                    try:
                        service.process_derived_secret(binding_context)
                        response = "OK"
                        print(f"[handler] Successfully processed DerivedSecret", flush=True)
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
            
            # Clean up old processed files (older than 60 seconds)
            import time
            current_time = time.time()
            for filename in list(processed):
                # Remove from processed set if file no longer exists
                if not os.path.exists(os.path.join(shared_dir, filename)):
                    processed.discard(filename)
            
            # Small delay to avoid busy loop
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
    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    # Initialize service
    service = DerivedSecretService()
    
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
