#!/bin/bash

# import-ceph-cluster.sh
# Simplified script to import external Ceph cluster for Kubernetes via Rook
# Based on create-external-cluster-resources.py and import-external-cluster.sh
# Only creates secrets and StorageClass, no CephCluster CR

set -euo pipefail

##############
# VARIABLES #
#############

# Default values (can be overridden by environment variables)
NAMESPACE=${NAMESPACE:-"rook-ceph"}
RBD_DATA_POOL_NAME=${RBD_DATA_POOL_NAME:-"k8s-rbd"}
CEPHFS_FILESYSTEM_NAME=${CEPHFS_FILESYSTEM_NAME:-"kubernetes"}
RGW_ENDPOINT=${RGW_ENDPOINT:-"blade001.zengarden.space:80"}
KUBECONFIG=${KUBECONFIG:-"/etc/rancher/k3s/k3s.yaml"}

# Fixed values based on Rook conventions
ROOK_RBD_FEATURES="layering"
RBD_PROVISIONER="rook-ceph.rbd.csi.ceph.com"
RBD_STORAGE_CLASS_NAME="ceph-rbd"
CSI_RBD_NODE_SECRET_NAME="csi-rbd-node"
CSI_RBD_PROVISIONER_SECRET_NAME="csi-rbd-provisioner"

# Set kubectl command
if [ -n "${KUBECONTEXT:-}" ]; then
    KUBECTL="kubectl --context=$KUBECONTEXT"
else
    KUBECTL="kubectl"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#############
# FUNCTIONS #
#############

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not available"
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is not available - please install jq package"
        exit 1
    fi
    
    # Check if cephadm is available
    if ! command -v cephadm &> /dev/null; then
        log_error "cephadm is not available"
        exit 1
    fi
    
    # Check if Ceph cluster is accessible
    if ! cephadm shell -- ceph status &> /dev/null; then
        log_error "Cannot access Ceph cluster via cephadm"
        exit 1
    fi
    
    log_info "All prerequisites validated successfully"
}

# Function to extract Ceph cluster information
extract_ceph_info() {
    log_info "Extracting Ceph cluster information..."
    
    # Get cluster FSID
    ROOK_EXTERNAL_FSID=$(cephadm shell -- ceph fsid)
    log_info "Cluster FSID: ${ROOK_EXTERNAL_FSID}"
    
    # Get monitor endpoints and data
    ROOK_EXTERNAL_CEPH_MON_DATA=$(cephadm shell -- ceph mon dump --format json | jq -r '.mons[] | "\(.name)=\(.addr | split("/")[0])"' | tr '\n' ',' | sed 's/,$//')
    log_info "Monitor data: ${ROOK_EXTERNAL_CEPH_MON_DATA}"
    
    # Get admin keyring
    ROOK_EXTERNAL_ADMIN_SECRET=$(cephadm shell -- ceph auth get-key client.admin)
    log_info "Admin key extracted (length: ${#ROOK_EXTERNAL_ADMIN_SECRET})"
    
    # For this simplified version, we use the admin secret as the monitor secret too
    ROOK_EXTERNAL_MONITOR_SECRET="${ROOK_EXTERNAL_ADMIN_SECRET}"
    
    # Set username
    ROOK_EXTERNAL_USERNAME="client.admin"
    ROOK_EXTERNAL_USER_SECRET="${ROOK_EXTERNAL_ADMIN_SECRET}"
}

# Function to create CSI users in Ceph
create_csi_users() {
    log_info "Creating CSI users in Ceph cluster..."
    
    # Create CSI RBD node user - delete existing if caps don't match
    log_info "Creating client.${CSI_RBD_NODE_SECRET_NAME} user..."
    if cephadm shell -- ceph auth get client.${CSI_RBD_NODE_SECRET_NAME} &>/dev/null; then
        log_warn "User client.${CSI_RBD_NODE_SECRET_NAME} already exists, deleting to recreate with correct capabilities..."
        cephadm shell -- ceph auth del client.${CSI_RBD_NODE_SECRET_NAME} || true
    fi
    cephadm shell -- ceph auth get-or-create client.${CSI_RBD_NODE_SECRET_NAME} \
        mon 'profile rbd, allow command "osd blocklist"' \
        osd 'profile rbd'
    CSI_RBD_NODE_SECRET=$(cephadm shell -- ceph auth get-key client.${CSI_RBD_NODE_SECRET_NAME})
    
    # Create CSI RBD provisioner user - delete existing if caps don't match
    log_info "Creating client.${CSI_RBD_PROVISIONER_SECRET_NAME} user..."
    if cephadm shell -- ceph auth get client.${CSI_RBD_PROVISIONER_SECRET_NAME} &>/dev/null; then
        log_warn "User client.${CSI_RBD_PROVISIONER_SECRET_NAME} already exists, deleting to recreate with correct capabilities..."
        cephadm shell -- ceph auth del client.${CSI_RBD_PROVISIONER_SECRET_NAME} || true
    fi
    cephadm shell -- ceph auth get-or-create client.${CSI_RBD_PROVISIONER_SECRET_NAME} \
        mon 'profile rbd, allow command "osd blocklist"' \
        mgr 'allow rw' \
        osd 'profile rbd'
    CSI_RBD_PROVISIONER_SECRET=$(cephadm shell -- ceph auth get-key client.${CSI_RBD_PROVISIONER_SECRET_NAME})
    
    log_info "CSI users created successfully"
}

# Function to create cluster namespace
create_cluster_namespace() {
    log_info "Creating cluster namespace: ${NAMESPACE}"
    
    if ! $KUBECTL get namespace "$NAMESPACE" &>/dev/null; then
        $KUBECTL create namespace "$NAMESPACE"
        log_info "Namespace ${NAMESPACE} created"
    else
        log_info "Namespace ${NAMESPACE} already exists"
    fi
}

# Function to import main secret
import_secret() {
    log_info "Creating/updating main cluster secret..."
    
    $KUBECTL create secret generic rook-ceph-mon \
        --namespace="$NAMESPACE" \
        --type="kubernetes.io/rook" \
        --from-literal=cluster-name="$NAMESPACE" \
        --from-literal=fsid="$ROOK_EXTERNAL_FSID" \
        --from-literal=admin-secret="$ROOK_EXTERNAL_ADMIN_SECRET" \
        --from-literal=mon-secret="$ROOK_EXTERNAL_MONITOR_SECRET" \
        --from-literal=ceph-username="$ROOK_EXTERNAL_USERNAME" \
        --from-literal=ceph-secret="$ROOK_EXTERNAL_USER_SECRET" \
        --dry-run=client -o yaml | $KUBECTL apply -f -
    
    log_info "Main cluster secret created/updated"
}

# Function to import config map
import_config_map() {
    log_info "Creating/updating monitor endpoints config map..."
    
    $KUBECTL create configmap rook-ceph-mon-endpoints \
        --namespace="$NAMESPACE" \
        --from-literal=data="$ROOK_EXTERNAL_CEPH_MON_DATA" \
        --from-literal=mapping="{}" \
        --from-literal=maxMonId="2" \
        --dry-run=client -o yaml | $KUBECTL apply -f -
    
    log_info "Monitor endpoints config map created/updated"
}

# Function to import CSI RBD node secret
import_csi_rbd_node_secret() {
    log_info "Creating/updating CSI RBD node secret..."
    
    # Delete existing secret if it exists to avoid immutable field errors
    if $KUBECTL get secret "rook-${CSI_RBD_NODE_SECRET_NAME}" -n "$NAMESPACE" &>/dev/null; then
        log_warn "Deleting existing secret rook-${CSI_RBD_NODE_SECRET_NAME} to recreate..."
        $KUBECTL delete secret "rook-${CSI_RBD_NODE_SECRET_NAME}" -n "$NAMESPACE" || true
    fi
    
    $KUBECTL create secret generic "rook-${CSI_RBD_NODE_SECRET_NAME}" \
        --namespace="$NAMESPACE" \
        --type="kubernetes.io/rook" \
        --from-literal=userID="$CSI_RBD_NODE_SECRET_NAME" \
        --from-literal=userKey="$CSI_RBD_NODE_SECRET"
    
    log_info "CSI RBD node secret created/updated"
}

# Function to import CSI RBD provisioner secret
import_csi_rbd_provisioner_secret() {
    log_info "Creating/updating CSI RBD provisioner secret..."
    
    # Delete existing secret if it exists to avoid immutable field errors
    if $KUBECTL get secret "rook-${CSI_RBD_PROVISIONER_SECRET_NAME}" -n "$NAMESPACE" &>/dev/null; then
        log_warn "Deleting existing secret rook-${CSI_RBD_PROVISIONER_SECRET_NAME} to recreate..."
        $KUBECTL delete secret "rook-${CSI_RBD_PROVISIONER_SECRET_NAME}" -n "$NAMESPACE" || true
    fi
    
    $KUBECTL create secret generic "rook-${CSI_RBD_PROVISIONER_SECRET_NAME}" \
        --namespace="$NAMESPACE" \
        --type="kubernetes.io/rook" \
        --from-literal=userID="$CSI_RBD_PROVISIONER_SECRET_NAME" \
        --from-literal=userKey="$CSI_RBD_PROVISIONER_SECRET"
    
    log_info "CSI RBD provisioner secret created/updated"
}

# Function to create RBD storage class
create_rbd_storage_class() {
    log_info "Creating/updating RBD storage class..."
    
    cat <<EOF | $KUBECTL apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $RBD_STORAGE_CLASS_NAME
provisioner: $RBD_PROVISIONER
parameters:
  clusterID: $NAMESPACE
  pool: $RBD_DATA_POOL_NAME
  imageFormat: "2"
  imageFeatures: $ROOK_RBD_FEATURES
  csi.storage.k8s.io/provisioner-secret-name: "rook-$CSI_RBD_PROVISIONER_SECRET_NAME"
  csi.storage.k8s.io/provisioner-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/controller-expand-secret-name: "rook-$CSI_RBD_PROVISIONER_SECRET_NAME"
  csi.storage.k8s.io/controller-expand-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/node-stage-secret-name: "rook-$CSI_RBD_NODE_SECRET_NAME"
  csi.storage.k8s.io/node-stage-secret-namespace: $NAMESPACE
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF
    
    log_info "RBD storage class created/updated"
}

# Function to ensure RBD pool exists
ensure_rbd_pool() {
    log_info "Ensuring RBD pool exists: ${RBD_DATA_POOL_NAME}"
    
    if ! cephadm shell -- ceph osd pool ls | grep -q "^${RBD_DATA_POOL_NAME}$"; then
        log_info "Creating RBD pool: ${RBD_DATA_POOL_NAME}"
        cephadm shell -- ceph osd pool create "${RBD_DATA_POOL_NAME}" 8 8
        cephadm shell -- ceph osd pool application enable "${RBD_DATA_POOL_NAME}" rbd
    else
        log_info "RBD pool ${RBD_DATA_POOL_NAME} already exists"
    fi
    
    # Initialize RBD pool
    cephadm shell -- rbd pool init "${RBD_DATA_POOL_NAME}" || true
    log_info "RBD pool ${RBD_DATA_POOL_NAME} is ready"
}

# Function to show usage
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --namespace <namespace>               Kubernetes namespace (default: rook-ceph)
  --rbd-data-pool-name <pool>          RBD data pool name (default: kubernetes)
  --cephfs-filesystem-name <fs>        CephFS filesystem name (default: kubernetes)
  --rgw-endpoint <endpoint>            RGW endpoint (default: blade001.zengarden.space:80)
  --kubeconfig <path>                  Path to kubeconfig (default: /etc/rancher/k3s/k3s.yaml)
  --help                               Show this help message

Environment Variables:
  NAMESPACE                            Same as --namespace
  RBD_DATA_POOL_NAME                   Same as --rbd-data-pool-name
  CEPHFS_FILESYSTEM_NAME               Same as --cephfs-filesystem-name
  RGW_ENDPOINT                         Same as --rgw-endpoint
  KUBECONFIG                           Same as --kubeconfig

Example:
  $0 --namespace rook-ceph --rbd-data-pool-name kubernetes

This script creates the necessary secrets and StorageClass to integrate
an external Ceph cluster with Rook in Kubernetes.
EOF
}

# Function to parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --rbd-data-pool-name)
                RBD_DATA_POOL_NAME="$2"
                shift 2
                ;;
            --cephfs-filesystem-name)
                CEPHFS_FILESYSTEM_NAME="$2"
                shift 2
                ;;
            --rgw-endpoint)
                RGW_ENDPOINT="$2"
                shift 2
                ;;
            --kubeconfig)
                KUBECONFIG="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to create external CephCluster CR
create_external_ceph_cluster() {
    log_info "Creating external CephCluster CR to deploy CSI drivers..."
    
    cat <<EOF | $KUBECTL apply -f -
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: external-ceph
  namespace: $NAMESPACE
spec:
  external:
    enable: true
  dataDirHostPath: /var/lib/rook
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.0
  mon:
    count: 3
    allowMultiplePerNode: false
  mgr:
    count: 2
    allowMultiplePerNode: false
  dashboard:
    enabled: false
  monitoring:
    enabled: false
  network:
    requireMsgr2: false
  crashCollector:
    disable: true
  logCollector:
    enabled: false
  cleanupPolicy:
    confirmation: ""
    sanitizeDisks:
      method: complete
      dataSource: zero
      iteration: 1
    allowUninstallWithVolumes: false
  placement:
    all:
      tolerations:
      - effect: NoSchedule
        key: node.kubernetes.io/unschedulable
        operator: Exists
      - effect: NoSchedule
        key: node.cloudprovider.kubernetes.io/uninitialized
        operator: Exists
  disruptionManagement:
    managePodBudgets: false
    osdMaintenanceTimeout: 30
    pgHealthCheckTimeout: 0
EOF
    
    log_info "External CephCluster CR created - waiting for CSI drivers to deploy..."
    
    # Wait for CSI driver pods to be ready
    log_info "Waiting for CSI RBD plugin to be ready..."
    $KUBECTL wait --for=condition=Ready --timeout=300s -n "$NAMESPACE" pod -l app=csi-rbdplugin || true
    
    log_info "CSI drivers should now be deploying"
}

########
# MAIN #
########

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    log_info "Starting Ceph external cluster integration..."
    log_info "================================================="
    log_info "Namespace: ${NAMESPACE}"
    log_info "RBD Pool: ${RBD_DATA_POOL_NAME}"
    log_info "CephFS: ${CEPHFS_FILESYSTEM_NAME}"
    log_info "RGW Endpoint: ${RGW_ENDPOINT}"
    log_info "Kubeconfig: ${KUBECONFIG}"
    log_info "================================================="
    
    # Validate environment
    validate_prerequisites
    
    # Extract information from Ceph cluster
    extract_ceph_info
    
    # Create CSI users in Ceph
    create_csi_users
    
    # Create cluster namespace
    create_cluster_namespace
    
    # Import secrets and config maps
    import_secret
    import_config_map
    import_csi_rbd_node_secret
    import_csi_rbd_provisioner_secret
    
    # Ensure RBD pool exists
    ensure_rbd_pool
    
    # Create external CephCluster CR to deploy CSI drivers
    create_external_ceph_cluster
    
    # Create storage class
    create_rbd_storage_class
    
    log_info "================================================="
    log_info "✅ Ceph external cluster integration completed successfully!"
    log_info ""
    log_info "Created resources:"
    log_info "- Namespace: ${NAMESPACE}"
    log_info "- Secret: rook-ceph-mon"
    log_info "- ConfigMap: rook-ceph-mon-endpoints"
    log_info "- Secret: rook-${CSI_RBD_NODE_SECRET_NAME}"
    log_info "- Secret: rook-${CSI_RBD_PROVISIONER_SECRET_NAME}"
    log_info "- StorageClass: ${RBD_STORAGE_CLASS_NAME}"
    log_info ""
    log_info "Next steps:"
    log_info "1. Deploy a CephCluster CR with external.enable=true"
    log_info "2. Test with a PVC using StorageClass: ${RBD_STORAGE_CLASS_NAME}"
    log_info "3. Monitor integration: kubectl get all -n ${NAMESPACE}"
}

# Execute main function with all arguments
main "$@"
