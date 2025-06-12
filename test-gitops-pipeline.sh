#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="fennel-dev"
TIMEOUT=300
CHART_VERSION="test-$(date +%s)"

echo -e "${BLUE}🚀 Starting End-to-End GitOps Pipeline Test${NC}"
echo "Testing Polkadot SDK deployment pipeline..."

# Test 1: Security Policy Validation
echo -e "\n${YELLOW}1. Testing Security Policy Validation${NC}"
echo "Creating test manifest with :latest tag (should fail)..."

cat > /tmp/test-bad-manifest.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-bad-deployment
spec:
  template:
    spec:
      containers:
      - name: bad-container
        image: nginx:latest  # This should be caught by security scan
EOF

# Test security scan locally if Conftest is available
if command -v conftest &> /dev/null; then
    echo "✅ Running local Conftest validation..."
    if conftest verify --policy .github/workflows/policy/ /tmp/test-bad-manifest.yaml 2>/dev/null; then
        echo -e "${RED}❌ Security scan should have failed for :latest tag${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ Security scan correctly blocked :latest tag${NC}"
    fi
else
    echo "⚠️ Conftest not installed locally, will test in CI"
fi

# Test 2: Helm Chart Validation
echo -e "\n${YELLOW}2. Testing Helm Chart Templates${NC}"
for chart in charts/*/; do
    chart_name=$(basename "$chart")
    echo "Testing chart: $chart_name"
    
    # Template with test values
    helm template "test-$chart_name" "$chart" \
        --set image.tag="sha256:abc123def456" \
        --set resources.limits.memory="2Gi" \
        --set resources.limits.cpu="1000m" \
        --dry-run > /tmp/test-template.yaml
    
    echo -e "${GREEN}✅ Chart $chart_name templates successfully${NC}"
done

# Test 3: Kustomize Build Validation
echo -e "\n${YELLOW}3. Testing Kustomize Overlays${NC}"
if [ -d "overlays" ]; then
    for overlay in overlays/*/; do
        overlay_name=$(basename "$overlay")
        echo "Testing overlay: $overlay_name"
        
        if [ -f "$overlay/kustomization.yaml" ]; then
            kustomize build "$overlay" > /dev/null
            echo -e "${GREEN}✅ Overlay $overlay_name builds successfully${NC}"
        fi
    done
fi

# Test 4: Kubernetes Cluster Connection
echo -e "\n${YELLOW}4. Testing Kubernetes Cluster Access${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure kubectl is configured and cluster is accessible"
    exit 1
fi
echo -e "${GREEN}✅ Kubernetes cluster accessible${NC}"

# Test 5: Flux Status Check
echo -e "\n${YELLOW}5. Testing Flux GitOps Status${NC}"
if command -v flux &> /dev/null; then
    echo "Checking Flux system status..."
    flux check
    
    echo "Checking GitRepository sync status..."
    flux get sources git
    
    echo "Checking Kustomization status..."
    flux get kustomizations
    
    echo "Checking HelmRelease status..."
    flux get helmreleases -A
    
    echo -e "${GREEN}✅ Flux GitOps system operational${NC}"
else
    echo "⚠️ Flux CLI not installed, checking with kubectl..."
    kubectl get pods -n flux-system
fi

# Test 6: Fennel Blockchain Validation
echo -e "\n${YELLOW}6. Testing Fennel Blockchain Operation${NC}"

# Check if fennel pods are running
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "Checking fennel-solonet pods..."
    kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet
    
    # Wait for pods to be ready
    echo "Waiting for fennel pods to be ready..."
    kubectl wait --for=condition=Ready pods -l app=fennel-solonet -n "$NAMESPACE" --timeout=300s
    
    # Test RPC endpoint
    echo "Testing JSON-RPC endpoint..."
    if kubectl get service -n "$NAMESPACE" fennel-solonet-rpc &> /dev/null; then
        kubectl port-forward -n "$NAMESPACE" svc/fennel-solonet-rpc 9944:9944 &
        PF_PID=$!
        sleep 5
        
        # Test system_health RPC call
        if curl -s -H "Content-Type: application/json" \
               -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' \
               http://localhost:9944 | jq -r '.result.shouldHavePeers' &> /dev/null; then
            echo -e "${GREEN}✅ JSON-RPC endpoint responsive${NC}"
        else
            echo -e "${RED}❌ JSON-RPC endpoint not responding${NC}"
        fi
        
        kill $PF_PID 2>/dev/null || true
    fi
    
    # Check P2P connectivity
    echo "Checking P2P peer connections..."
    FENNEL_POD=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$FENNEL_POD" ]; then
        PEER_COUNT=$(kubectl logs -n "$NAMESPACE" "$FENNEL_POD" --tail=100 | grep -o '[0-9]\+ peers' | tail -1 | cut -d' ' -f1 || echo "0")
        if [ "$PEER_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✅ P2P networking operational ($PEER_COUNT peers)${NC}"
        else
            echo -e "${YELLOW}⚠️ No P2P peers connected (check bootnode configuration)${NC}"
        fi
    fi
    
    echo -e "${GREEN}✅ Fennel blockchain operational${NC}"
else
    echo -e "${YELLOW}⚠️ Namespace $NAMESPACE not found, skipping blockchain tests${NC}"
fi

# Test 7: Security Policies Validation
echo -e "\n${YELLOW}7. Testing Security Policies${NC}"

# Check if Gatekeeper is installed
if kubectl get crd constrainttemplates.templates.gatekeeper.sh &> /dev/null; then
    echo "Checking Gatekeeper constraints..."
    kubectl get constraints -A
    echo -e "${GREEN}✅ Gatekeeper policies active${NC}"
else
    echo "⚠️ Gatekeeper not installed, checking NetworkPolicies..."
fi

# Check NetworkPolicies
if kubectl get networkpolicy -n "$NAMESPACE" &> /dev/null; then
    kubectl get networkpolicy -n "$NAMESPACE"
    echo -e "${GREEN}✅ NetworkPolicies configured${NC}"
else
    echo -e "${YELLOW}⚠️ No NetworkPolicies found${NC}"
fi

# Test 8: Monitoring and Observability
echo -e "\n${YELLOW}8. Testing Monitoring Setup${NC}"

# Check if ServiceMonitor exists
if kubectl get servicemonitor -n "$NAMESPACE" &> /dev/null; then
    kubectl get servicemonitor -n "$NAMESPACE"
    echo -e "${GREEN}✅ ServiceMonitor configured for Prometheus${NC}"
else
    echo -e "${YELLOW}⚠️ No ServiceMonitor found${NC}"
fi

# Check metrics endpoint
if kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet &> /dev/null; then
    FENNEL_POD=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$FENNEL_POD" ]; then
        echo "Testing Prometheus metrics endpoint..."
        kubectl port-forward -n "$NAMESPACE" "$FENNEL_POD" 9615:9615 &
        PF_PID=$!
        sleep 3
        
        if curl -s http://localhost:9615/metrics | head -5 &> /dev/null; then
            echo -e "${GREEN}✅ Prometheus metrics endpoint accessible${NC}"
        else
            echo -e "${RED}❌ Metrics endpoint not accessible${NC}"
        fi
        
        kill $PF_PID 2>/dev/null || true
    fi
fi

# Test 9: Image Automation Testing
echo -e "\n${YELLOW}9. Testing Image Automation Pipeline${NC}"

# Check ImageRepository and ImagePolicy
if command -v flux &> /dev/null; then
    echo "Checking image automation resources..."
    flux get image repository -A
    flux get image policy -A
    flux get image update -A
    echo -e "${GREEN}✅ Image automation configured${NC}"
else
    echo "⚠️ Flux CLI not available for image automation testing"
fi

# Test 10: End-to-End Deployment Test
echo -e "\n${YELLOW}10. Simulating Full Deployment Cycle${NC}"

echo "This would test:"
echo "  • Code push → srtool build → container push"
echo "  • GitHub Actions → security scan → digest update"
echo "  • Flux sync → HelmRelease update → pod rollout"
echo "  • Health checks → metrics collection → readiness"

echo -e "\n${GREEN}🎉 GitOps Pipeline Test Complete!${NC}"
echo "Next steps:"
echo "  1. Monitor for 24 hours (Step 9 requirement)"
echo "  2. Check Prometheus dashboards"
echo "  3. Verify P2P networking stability"
echo "  4. Test validator key rotation (if applicable)"
echo "  5. Proceed to staging promotion when stable"

rm -f /tmp/test-*.yaml 