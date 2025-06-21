#!/bin/bash
set -euo pipefail

CHART_DIR="/home/oleksiyp/dev/zengarden/basic-infra/helmfile/gitea/charts/gitea-org-creator"

echo "🔍 Testing Gitea Organization Creator Chart"

# Test 1: Helm template validation
echo "1️⃣  Testing Helm template rendering..."
if helm template test-org-creator "$CHART_DIR" --debug > /tmp/gitea-org-creator-test.yaml; then
    echo "✅ Helm template renders successfully"
else
    echo "❌ Helm template rendering failed"
    exit 1
fi

# Test 2: Validate Kubernetes manifests
echo "2️⃣  Validating generated Kubernetes manifests..."
if kubectl apply --dry-run=client -f /tmp/gitea-org-creator-test.yaml; then
    echo "✅ Generated manifests are valid"
else
    echo "❌ Generated manifests validation failed"
    exit 1
fi

# Test 3: Check if script is properly embedded
echo "3️⃣  Checking if script is embedded in ConfigMap..."
if grep -q "create-org.sh" /tmp/gitea-org-creator-test.yaml; then
    echo "✅ Script is embedded in ConfigMap"
else
    echo "❌ Script is not found in ConfigMap"
    exit 1
fi

# Test 4: Verify security contexts
echo "4️⃣  Verifying security contexts..."
if grep -q "runAsNonRoot: true" /tmp/gitea-org-creator-test.yaml && \
   grep -q "runAsUser: 1000" /tmp/gitea-org-creator-test.yaml; then
    echo "✅ Security contexts are properly configured"
else
    echo "❌ Security contexts are missing or incorrect"
    exit 1
fi

# Test 5: Check environment variables
echo "5️⃣  Checking environment variables..."
if grep -q "ORG_NAME" /tmp/gitea-org-creator-test.yaml && \
   grep -q "GITEA_SERVICE_NAME" /tmp/gitea-org-creator-test.yaml; then
    echo "✅ Environment variables are configured"
else
    echo "❌ Environment variables are missing"
    exit 1
fi

echo ""
echo "🎉 All tests passed! Chart is ready for deployment."
echo ""
echo "To deploy the chart:"
echo "  helm install gitea-org-creator $CHART_DIR -n gitea"
echo ""
echo "Generated manifests saved to: /tmp/gitea-org-creator-test.yaml"
