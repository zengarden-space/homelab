#!/bin/bash

echo "=========================================="
echo "     Ceph Cluster Service Status"
echo "=========================================="
echo

# Check if we can connect to Ceph
if ! cephadm shell -- ceph status &>/dev/null; then
    echo "❌ Cannot connect to Ceph cluster"
    echo "Please ensure you're running this from a Ceph host and the cluster is operational"
    exit 1
fi

echo "📊 Cluster Overview:"
cephadm shell -- ceph status
echo

echo "🔧 Service Status:"
echo

# Core services
echo "Core Services:"
echo "  Monitors:"
cephadm shell -- ceph orch ls mon --format json | jq -r '.[0].placement.hosts[]?' 2>/dev/null | sed 's/^/    - /' || echo "    - No monitors configured"

echo "  Managers:"
cephadm shell -- ceph orch ls mgr --format json | jq -r '.[0].placement.hosts[]?' 2>/dev/null | sed 's/^/    - /' || echo "    - No managers configured"

echo

# Additional services
echo "Additional Services:"

# RGW
echo "  Object Gateway (RGW):"
if cephadm shell -- ceph orch ls rgw --format json 2>/dev/null | jq -e '.[0]' &>/dev/null; then
    echo "    ✅ Running on:"
    cephadm shell -- ceph orch ps --service_name rgw.default --format json 2>/dev/null | jq -r '.[].hostname' | sed 's/^/      - /' || echo "      - Status unknown"
    echo "    📡 Endpoint: http://<host>:80"
else
    echo "    ❌ Not deployed"
fi

# NFS
echo "  NFS Service:"
if cephadm shell -- ceph orch ls nfs --format json 2>/dev/null | jq -e '.[0]' &>/dev/null; then
    echo "    ✅ Running on:"
    cephadm shell -- ceph orch ps --service_name nfs.nfs-cluster --format json 2>/dev/null | jq -r '.[].hostname' | sed 's/^/      - /' || echo "      - Status unknown"
else
    echo "    ❌ Not deployed"
fi

# SMB
echo "  SMB Service:"
if cephadm shell -- ceph orch ls smb --format json 2>/dev/null | jq -e '.[0]' &>/dev/null; then
    echo "    ✅ Running on:"
    cephadm shell -- ceph orch ps --service_name smb.smb-cluster --format json 2>/dev/null | jq -r '.[].hostname' | sed 's/^/      - /' || echo "      - Status unknown"
else
    echo "    ❌ Not deployed"
fi

echo

echo "📚 Quick Commands:"
echo "  View all services: cephadm shell -- ceph orch ls"
echo "  Check service details: cephadm shell -- ceph orch ps"
echo "  View cluster health: cephadm shell -- ceph health detail"
echo "  Access dashboard: https://<any-host>:8443 (admin/admin123)"
echo

echo "📖 For detailed service configuration, see SERVICES.md"
echo "=========================================="
