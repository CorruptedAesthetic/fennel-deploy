#!/bin/bash
# Test PoA deployment script - Launch everything, test, then tear down

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Fennel PoA Test Deployment ===${NC}"

# Configuration
NAMESPACE="fennel-test"
TIMEOUT="300s"

# Function to cleanup
cleanup() {
    echo -e "\n${YELLOW}Cleaning up test deployment...${NC}"
    
    # Delete namespace (removes everything)
    kubectl delete namespace $NAMESPACE --ignore-not-found=true
    
    # Remove test chain data
    rm -rf /tmp/fennel-test-*
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Set trap for cleanup on exit
trap cleanup EXIT

echo -e "\n${GREEN}Step 1: Create test namespace${NC}"
kubectl create namespace $NAMESPACE || true

echo -e "\n${GREEN}Step 2: Deploy test chain${NC}"
# Copy your current dev deployment but in test namespace
kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: fennel-test-config
data:
  test-mode: "true"
  chain-spec: "custom-poa"
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: fennel-test-node
spec:
  serviceName: fennel-test
  replicas: 1
  selector:
    matchLabels:
      app: fennel-test
  template:
    metadata:
      labels:
        app: fennel-test
    spec:
      containers:
      - name: fennel-node
        image: ghcr.io/neurosx/fennel-node:latest
        args:
        - "--dev"
        - "--tmp"
        - "--chain=local"  # Change to custom spec when ready
        - "--alice"
        - "--port=30333"
        - "--rpc-port=9944"
        - "--rpc-external"
        - "--rpc-cors=all"
        ports:
        - containerPort: 9944
          name: rpc
        - containerPort: 30333
          name: p2p
---
apiVersion: v1
kind: Service
metadata:
  name: fennel-test-rpc
spec:
  selector:
    app: fennel-test
  ports:
  - port: 9944
    name: rpc
EOF

echo -e "\n${GREEN}Step 3: Wait for pod to be ready${NC}"
kubectl wait --for=condition=ready pod -l app=fennel-test -n $NAMESPACE --timeout=$TIMEOUT

echo -e "\n${GREEN}Step 4: Test blockchain operations${NC}"
POD_NAME=$(kubectl get pod -n $NAMESPACE -l app=fennel-test -o jsonpath='{.items[0].metadata.name}')

# Check if node is producing blocks
kubectl exec -n $NAMESPACE $POD_NAME -- curl -s -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"system_health","params":[],"id":1}' \
  http://localhost:9944 | jq .

echo -e "\n${GREEN}Step 5: Test PoA operations${NC}"
# Port forward for testing
kubectl port-forward -n $NAMESPACE $POD_NAME 9944:9944 &
PF_PID=$!
sleep 5

# You can now connect with Polkadot.js to localhost:9944
echo -e "${YELLOW}RPC available at: http://localhost:9944${NC}"
echo -e "${YELLOW}Connect with Polkadot.js to test PoA operations${NC}"

echo -e "\n${GREEN}Step 6: Run automated tests${NC}"
# Add your automated tests here
# - Check block production
# - Test validator management
# - Verify sudo operations

echo -e "\n${YELLOW}Test deployment is running!${NC}"
echo "Press any key to tear down the test deployment..."
read -n 1 -s

# Kill port forward
kill $PF_PID 2>/dev/null || true

echo -e "\n${GREEN}Test complete! Cleaning up...${NC}"
# Cleanup happens automatically via trap 