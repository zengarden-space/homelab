#!/usr/bin/env python3
"""
Grafana Alert Operator Service
Reconciles Kubernetes CRDs with Grafana Alerting API
"""

import os
import sys
import time
import json
import base64
import signal
import logging
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List

import requests
from kubernetes import client, config

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)


class GrafanaClient:
    """Client for Grafana Alerting HTTP API"""

    def __init__(self, url: str, token: str, org_id: int = 1, disable_provenance: bool = True):
        self.url = url.rstrip('/')
        self.token = token
        self.org_id = org_id
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
            'X-Grafana-Org-Id': str(org_id)
        })
        if disable_provenance:
            self.session.headers['X-Disable-Provenance'] = 'true'

    @classmethod
    def from_secret(cls, k8s_client: client.CoreV1Api, secret_ref: Dict[str, str],
                    default_namespace: str = 'default') -> 'GrafanaClient':
        """Create GrafanaClient from Kubernetes Secret reference"""
        namespace = secret_ref.get('namespace', default_namespace)
        name = secret_ref.get('name')
        token_key = secret_ref.get('key', 'token')

        try:
            secret = k8s_client.read_namespaced_secret(name, namespace)
        except Exception as e:
            raise ValueError(f"Failed to read secret {namespace}/{name}: {e}")

        # Decode secret data
        if token_key not in secret.data:
            raise ValueError(f"Secret {namespace}/{name} missing key '{token_key}'")

        token = base64.b64decode(secret.data[token_key]).decode('utf-8')
        url = base64.b64decode(secret.data.get('url', b'')).decode('utf-8')
        org_id = int(base64.b64decode(secret.data.get('orgId', b'1')).decode('utf-8'))

        if not url:
            raise ValueError(f"Secret {namespace}/{name} missing 'url' field")

        return cls(url=url, token=token, org_id=org_id)

    # Alert Rules API
    def list_alert_rules(self) -> List[Dict[str, Any]]:
        """List all alert rules"""
        resp = self.session.get(f'{self.url}/api/v1/provisioning/alert-rules')
        resp.raise_for_status()
        return resp.json()

    def get_alert_rule(self, uid: str) -> Optional[Dict[str, Any]]:
        """Get alert rule by UID"""
        resp = self.session.get(f'{self.url}/api/v1/provisioning/alert-rules/{uid}')
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        return resp.json()

    def create_alert_rule(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Create new alert rule"""
        resp = self.session.post(f'{self.url}/api/v1/provisioning/alert-rules', json=payload)
        resp.raise_for_status()
        return resp.json()

    def update_alert_rule(self, uid: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Update existing alert rule"""
        resp = self.session.put(f'{self.url}/api/v1/provisioning/alert-rules/{uid}', json=payload)
        resp.raise_for_status()
        return resp.json()

    def delete_alert_rule(self, uid: str) -> None:
        """Delete alert rule"""
        resp = self.session.delete(f'{self.url}/api/v1/provisioning/alert-rules/{uid}')
        if resp.status_code != 404:  # Ignore if already deleted
            resp.raise_for_status()

    # Notification Policies API
    def get_notification_policy(self) -> Dict[str, Any]:
        """Get notification policy tree"""
        resp = self.session.get(f'{self.url}/api/v1/provisioning/policies')
        resp.raise_for_status()
        return resp.json()

    def update_notification_policy(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Update notification policy tree"""
        resp = self.session.put(f'{self.url}/api/v1/provisioning/policies', json=payload)
        resp.raise_for_status()
        return resp.json()

    # Mute Timings API
    def list_mute_timings(self) -> List[Dict[str, Any]]:
        """List all mute timings"""
        resp = self.session.get(f'{self.url}/api/v1/provisioning/mute-timings')
        resp.raise_for_status()
        return resp.json()

    def get_mute_timing(self, name: str) -> Optional[Dict[str, Any]]:
        """Get mute timing by name"""
        resp = self.session.get(f'{self.url}/api/v1/provisioning/mute-timings/{name}')
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        return resp.json()

    def create_mute_timing(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Create new mute timing"""
        resp = self.session.post(f'{self.url}/api/v1/provisioning/mute-timings', json=payload)
        resp.raise_for_status()
        return resp.json()

    def update_mute_timing(self, name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Update existing mute timing"""
        resp = self.session.put(f'{self.url}/api/v1/provisioning/mute-timings/{name}', json=payload)
        resp.raise_for_status()
        return resp.json()

    def delete_mute_timing(self, name: str) -> None:
        """Delete mute timing"""
        resp = self.session.delete(f'{self.url}/api/v1/provisioning/mute-timings/{name}')
        if resp.status_code != 404:
            resp.raise_for_status()

    # Templates API
    def list_templates(self) -> List[Dict[str, Any]]:
        """List all notification templates"""
        resp = self.session.get(f'{self.url}/api/v1/provisioning/templates')
        resp.raise_for_status()
        return resp.json()

    def get_template(self, name: str) -> Optional[Dict[str, Any]]:
        """Get template by name"""
        resp = self.session.get(f'{self.url}/api/v1/provisioning/templates/{name}')
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        return resp.json()

    def create_template(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Create new template"""
        resp = self.session.put(f'{self.url}/api/v1/provisioning/templates/{payload["name"]}', json=payload)
        resp.raise_for_status()
        return resp.json()

    def update_template(self, name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Update existing template"""
        resp = self.session.put(f'{self.url}/api/v1/provisioning/templates/{name}', json=payload)
        resp.raise_for_status()
        return resp.json()

    def delete_template(self, name: str) -> None:
        """Delete template"""
        resp = self.session.delete(f'{self.url}/api/v1/provisioning/templates/{name}')
        if resp.status_code != 404:
            resp.raise_for_status()


class GrafanaAlertOperatorService:
    """Main service for reconciling Grafana alert resources"""

    def __init__(self):
        self.running = True
        self.shared_dir = '/shared'

        # Initialize Kubernetes client
        try:
            config.load_incluster_config()
        except:
            config.load_kube_config()

        self.k8s_core = client.CoreV1Api()
        self.k8s_custom = client.CustomObjectsApi()

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT, self._handle_shutdown)

        logger.info("Grafana Alert Operator Service initialized")

    def _handle_shutdown(self, signum, frame):
        """Handle graceful shutdown"""
        logger.info(f"Received signal {signum}, shutting down...")
        self.running = False

    def run(self):
        """Main service loop"""
        logger.info("Starting service loop...")

        while self.running:
            try:
                # Check for request files
                request_files = [f for f in os.listdir(self.shared_dir)
                               if f.startswith('request-') and f.endswith('.json')]

                for request_file in request_files:
                    request_path = os.path.join(self.shared_dir, request_file)
                    response_path = request_path.replace('request-', 'response-').replace('.json', '.txt')

                    try:
                        # Read request
                        with open(request_path, 'r') as f:
                            request = json.load(f)

                        logger.info(f"Processing request: {request.get('binding', {}).get('type', 'unknown')}")

                        # Process request
                        result = self._process_request(request)

                        # Write response
                        with open(response_path, 'w') as f:
                            f.write(result)

                        logger.info(f"Request processed successfully")

                    except Exception as e:
                        logger.error(f"Error processing request: {e}", exc_info=True)
                        with open(response_path, 'w') as f:
                            f.write(f"ERROR: {str(e)}")
                    finally:
                        # Clean up request file
                        try:
                            os.remove(request_path)
                        except:
                            pass

                # Sleep before next iteration
                time.sleep(1)
                sys.stdout.flush()

            except Exception as e:
                logger.error(f"Error in main loop: {e}", exc_info=True)
                time.sleep(5)

        logger.info("Service stopped")

    def _process_request(self, request: Dict[str, Any]) -> str:
        """Process a reconciliation request"""
        binding = request.get('binding', {})
        event_type = binding.get('type')

        if event_type == 'Synchronization':
            return self._handle_synchronization(binding)
        elif event_type in ['Added', 'Modified']:
            return self._handle_change(binding)
        elif event_type == 'Deleted':
            return self._handle_deletion(binding)
        else:
            return f"Unknown event type: {event_type}"

    def _handle_synchronization(self, binding: Dict[str, Any]) -> str:
        """Handle initial synchronization"""
        logger.info("Handling synchronization")
        # Process all resources
        self._reconcile_all_alert_rules()
        self._reconcile_all_notification_policies()
        self._reconcile_all_mute_timings()
        self._reconcile_all_templates()
        return "Synchronization complete"

    def _handle_change(self, binding: Dict[str, Any]) -> str:
        """Handle resource creation or modification"""
        watch_event = binding.get('watchEvent', {})
        resource = watch_event.get('object', {})
        kind = resource.get('kind')
        name = resource.get('metadata', {}).get('name')
        namespace = resource.get('metadata', {}).get('namespace')

        logger.info(f"Reconciling {kind} {namespace}/{name}")

        try:
            if kind == 'GrafanaAlertRule':
                self._reconcile_alert_rule(resource)
            elif kind == 'GrafanaNotificationPolicy':
                self._reconcile_notification_policy(resource)
            elif kind == 'GrafanaMuteTiming':
                self._reconcile_mute_timing(resource)
            elif kind == 'GrafanaNotificationTemplate':
                self._reconcile_template(resource)
            else:
                return f"Unknown resource kind: {kind}"

            return f"Successfully reconciled {kind} {namespace}/{name}"

        except Exception as e:
            logger.error(f"Failed to reconcile {kind} {namespace}/{name}: {e}", exc_info=True)
            self._update_status_failed(resource, str(e))
            raise

    def _handle_deletion(self, binding: Dict[str, Any]) -> str:
        """Handle resource deletion"""
        watch_event = binding.get('watchEvent', {})
        resource = watch_event.get('object', {})
        kind = resource.get('kind')
        name = resource.get('metadata', {}).get('name')
        namespace = resource.get('metadata', {}).get('namespace')

        logger.info(f"Handling deletion of {kind} {namespace}/{name}")

        try:
            if kind == 'GrafanaAlertRule':
                self._delete_alert_rule(resource)
            elif kind == 'GrafanaMuteTiming':
                self._delete_mute_timing(resource)
            elif kind == 'GrafanaNotificationTemplate':
                self._delete_template(resource)

            return f"Successfully deleted {kind} {namespace}/{name}"

        except Exception as e:
            logger.error(f"Failed to delete {kind} {namespace}/{name}: {e}", exc_info=True)
            raise

    def _reconcile_alert_rule(self, resource: Dict[str, Any]) -> None:
        """Reconcile a GrafanaAlertRule resource"""
        spec = resource['spec']
        status = resource.get('status', {})
        metadata = resource['metadata']

        # Create Grafana client
        grafana = GrafanaClient.from_secret(
            self.k8s_core,
            spec['grafanaRef']['secretRef'],
            metadata['namespace']
        )

        # Build alert rule payload
        payload = {
            'folderUID': spec['folderUID'],
            'ruleGroup': spec['ruleGroup'],
            'title': spec['title'],
            'condition': spec['condition'],
            'noDataState': spec.get('noDataState', 'NoData'),
            'execErrState': spec.get('execErrState', 'Alerting'),
            'for': spec.get('for', '0s'),
            'annotations': spec.get('annotations', {}),
            'labels': spec.get('labels', {}),
            'data': spec['data']
        }

        # Check if alert rule exists
        existing_uid = status.get('uid')
        existing_rule = None

        if existing_uid:
            existing_rule = grafana.get_alert_rule(existing_uid)

        # Create or update
        if existing_rule:
            payload['uid'] = existing_uid
            result = grafana.update_alert_rule(existing_uid, payload)
            logger.info(f"Updated alert rule {result['uid']}")
        else:
            result = grafana.create_alert_rule(payload)
            logger.info(f"Created alert rule {result['uid']}")

        # Update status
        self._update_status(resource, {
            'uid': result['uid'],
            'provenance': result.get('provenance', ''),
            'lastSynced': datetime.now(timezone.utc).isoformat(),
            'syncStatus': 'Synced',
            'message': ''
        })

    def _reconcile_notification_policy(self, resource: Dict[str, Any]) -> None:
        """Reconcile a GrafanaNotificationPolicy resource"""
        spec = resource['spec']
        metadata = resource['metadata']

        # Create Grafana client
        grafana = GrafanaClient.from_secret(
            self.k8s_core,
            spec['grafanaRef']['secretRef'],
            metadata['namespace']
        )

        # Get current policy tree
        current_policy = grafana.get_notification_policy()

        # Build policy payload
        payload = {
            'receiver': spec['receiver'],
            'group_by': spec.get('groupBy', ['grafana_folder', 'alertname']),
            'group_wait': spec.get('groupWait', '30s'),
            'group_interval': spec.get('groupInterval', '5m'),
            'repeat_interval': spec.get('repeatInterval', '4h')
        }

        if 'matchers' in spec:
            payload['object_matchers'] = [
                [m['label'], m['match'], m['value']]
                for m in spec['matchers']
            ]

        if 'muteTimeIntervals' in spec:
            payload['mute_time_intervals'] = spec['muteTimeIntervals']

        if 'routes' in spec:
            payload['routes'] = spec['routes']

        # Update policy
        grafana.update_notification_policy(payload)
        logger.info(f"Updated notification policy")

        # Update status
        self._update_status(resource, {
            'lastSynced': datetime.now(timezone.utc).isoformat(),
            'syncStatus': 'Synced',
            'message': ''
        })

    def _reconcile_mute_timing(self, resource: Dict[str, Any]) -> None:
        """Reconcile a GrafanaMuteTiming resource"""
        spec = resource['spec']
        metadata = resource['metadata']

        # Create Grafana client
        grafana = GrafanaClient.from_secret(
            self.k8s_core,
            spec['grafanaRef']['secretRef'],
            metadata['namespace']
        )

        # Build payload
        payload = {
            'name': spec['name'],
            'time_intervals': spec['timeIntervals']
        }

        # Check if exists
        existing = grafana.get_mute_timing(spec['name'])

        # Create or update
        if existing:
            result = grafana.update_mute_timing(spec['name'], payload)
            logger.info(f"Updated mute timing {spec['name']}")
        else:
            result = grafana.create_mute_timing(payload)
            logger.info(f"Created mute timing {spec['name']}")

        # Update status
        self._update_status(resource, {
            'version': result.get('version', 0),
            'lastSynced': datetime.now(timezone.utc).isoformat(),
            'syncStatus': 'Synced',
            'message': ''
        })

    def _reconcile_template(self, resource: Dict[str, Any]) -> None:
        """Reconcile a GrafanaNotificationTemplate resource"""
        spec = resource['spec']
        metadata = resource['metadata']

        # Create Grafana client
        grafana = GrafanaClient.from_secret(
            self.k8s_core,
            spec['grafanaRef']['secretRef'],
            metadata['namespace']
        )

        # Build payload
        payload = {
            'name': spec['name'],
            'template': spec['template']
        }

        # Check if exists
        existing = grafana.get_template(spec['name'])

        # Create or update
        if existing:
            result = grafana.update_template(spec['name'], payload)
            logger.info(f"Updated template {spec['name']}")
        else:
            result = grafana.create_template(payload)
            logger.info(f"Created template {spec['name']}")

        # Update status
        self._update_status(resource, {
            'version': result.get('version', 0),
            'lastSynced': datetime.now(timezone.utc).isoformat(),
            'syncStatus': 'Synced',
            'message': ''
        })

    def _delete_alert_rule(self, resource: Dict[str, Any]) -> None:
        """Delete alert rule from Grafana"""
        spec = resource['spec']
        status = resource.get('status', {})
        metadata = resource['metadata']

        uid = status.get('uid')
        if not uid:
            logger.info("No UID in status, nothing to delete")
            return

        # Create Grafana client
        grafana = GrafanaClient.from_secret(
            self.k8s_core,
            spec['grafanaRef']['secretRef'],
            metadata['namespace']
        )

        grafana.delete_alert_rule(uid)
        logger.info(f"Deleted alert rule {uid}")

    def _delete_mute_timing(self, resource: Dict[str, Any]) -> None:
        """Delete mute timing from Grafana"""
        spec = resource['spec']
        metadata = resource['metadata']

        # Create Grafana client
        grafana = GrafanaClient.from_secret(
            self.k8s_core,
            spec['grafanaRef']['secretRef'],
            metadata['namespace']
        )

        grafana.delete_mute_timing(spec['name'])
        logger.info(f"Deleted mute timing {spec['name']}")

    def _delete_template(self, resource: Dict[str, Any]) -> None:
        """Delete template from Grafana"""
        spec = resource['spec']
        metadata = resource['metadata']

        # Create Grafana client
        grafana = GrafanaClient.from_secret(
            self.k8s_core,
            spec['grafanaRef']['secretRef'],
            metadata['namespace']
        )

        grafana.delete_template(spec['name'])
        logger.info(f"Deleted template {spec['name']}")

    def _reconcile_all_alert_rules(self) -> None:
        """Reconcile all GrafanaAlertRule resources"""
        try:
            resources = self.k8s_custom.list_cluster_custom_object(
                group='monitoring.zengarden.space',
                version='v1',
                plural='grafanaalertrules'
            )

            for resource in resources.get('items', []):
                try:
                    self._reconcile_alert_rule(resource)
                except Exception as e:
                    logger.error(f"Failed to reconcile alert rule: {e}")
        except Exception as e:
            logger.error(f"Failed to list alert rules: {e}")

    def _reconcile_all_notification_policies(self) -> None:
        """Reconcile all GrafanaNotificationPolicy resources"""
        try:
            resources = self.k8s_custom.list_cluster_custom_object(
                group='monitoring.zengarden.space',
                version='v1',
                plural='grafananotificationpolicies'
            )

            for resource in resources.get('items', []):
                try:
                    self._reconcile_notification_policy(resource)
                except Exception as e:
                    logger.error(f"Failed to reconcile notification policy: {e}")
        except Exception as e:
            logger.error(f"Failed to list notification policies: {e}")

    def _reconcile_all_mute_timings(self) -> None:
        """Reconcile all GrafanaMuteTiming resources"""
        try:
            resources = self.k8s_custom.list_cluster_custom_object(
                group='monitoring.zengarden.space',
                version='v1',
                plural='grafanamutetimings'
            )

            for resource in resources.get('items', []):
                try:
                    self._reconcile_mute_timing(resource)
                except Exception as e:
                    logger.error(f"Failed to reconcile mute timing: {e}")
        except Exception as e:
            logger.error(f"Failed to list mute timings: {e}")

    def _reconcile_all_templates(self) -> None:
        """Reconcile all GrafanaNotificationTemplate resources"""
        try:
            resources = self.k8s_custom.list_cluster_custom_object(
                group='monitoring.zengarden.space',
                version='v1',
                plural='grafananotificationtemplates'
            )

            for resource in resources.get('items', []):
                try:
                    self._reconcile_template(resource)
                except Exception as e:
                    logger.error(f"Failed to reconcile template: {e}")
        except Exception as e:
            logger.error(f"Failed to list templates: {e}")

    def _update_status(self, resource: Dict[str, Any], status: Dict[str, Any]) -> None:
        """Update resource status"""
        try:
            metadata = resource['metadata']
            kind = resource['kind']

            # Map kind to plural
            plural_map = {
                'GrafanaAlertRule': 'grafanaalertrules',
                'GrafanaNotificationPolicy': 'grafananotificationpolicies',
                'GrafanaMuteTiming': 'grafanamutetimings',
                'GrafanaNotificationTemplate': 'grafananotificationtemplates'
            }

            self.k8s_custom.patch_namespaced_custom_object_status(
                group='monitoring.zengarden.space',
                version='v1',
                namespace=metadata['namespace'],
                plural=plural_map[kind],
                name=metadata['name'],
                body={'status': status}
            )
        except Exception as e:
            logger.error(f"Failed to update status: {e}")

    def _update_status_failed(self, resource: Dict[str, Any], message: str) -> None:
        """Update resource status to Failed"""
        self._update_status(resource, {
            'syncStatus': 'Failed',
            'message': message,
            'lastSynced': datetime.now(timezone.utc).isoformat()
        })


if __name__ == '__main__':
    service = GrafanaAlertOperatorService()
    service.run()
