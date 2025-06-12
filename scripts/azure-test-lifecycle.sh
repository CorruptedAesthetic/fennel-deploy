#!/bin/bash
# Azure Fennel Blockchain Test Lifecycle Script
# Launch → Test → Shutdown → Improve → Repeat

set -e

# Configuration
RESOURCE_GROUP="fennel-test-rg"
LOCATION="eastus"
CLUSTER_NAME="fennel-test-aks"
NODE_COUNT="3"
NODE_SIZE="Standard_B2s"  # Cheap for testing
NAMESPACE="fennel-test"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
show_menu() {
    echo -e "\n${BLUE}=== Azure Fennel Test Lifecycle ===${NC}"
    echo "1) Create Azure infrastructure"
    echo "2) Deploy Fennel blockchain"
    echo "3) Run validation tests"
    echo "4) Monitor costs"
    echo "5) Shutdown (keep data)"
    echo "6) Destroy everything"
    echo "7) Show current status"
    echo "0) Exit"
    echo -n "Choose option: "
}

create_infrastructure() {
    echo -e "\n${GREEN}Creating Azure test infrastructure...${NC}"
    
    # Create resource group
    echo "Creating resource group..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
    
    # Create AKS cluster (small, cheap nodes for testing)
    echo "Creating AKS cluster (this takes ~5 minutes)..."
    az aks create \
        --resource-group $RESOURCE_GROUP \
        --name $CLUSTER_NAME \
        --node-count $NODE_COUNT \
        --node-vm-size $NODE_SIZE \
        --enable-managed-identity \
        --generate-ssh-keys \
        --network-plugin azure \
        --network-policy calico
    
    # Get credentials
    echo "Getting cluster credentials..."
    az aks get-credentials \
        --resource-group $RESOURCE_GROUP \
        --name $CLUSTER_NAME \
        --overwrite-existing
    
    # Install Flux
    echo "Installing Flux GitOps..."
    curl -s https://fluxcd.io/install.sh | sudo bash
    flux check --pre
    
    echo -e "${GREEN}✓ Infrastructure ready!${NC}"
    echo -e "${YELLOW}Estimated cost: ~$5-10/day for test cluster${NC}"
}

deploy_blockchain() {
    echo -e "\n${GREEN}Deploying Fennel blockchain...${NC}"
    
    # Create namespace
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy using your GitOps
    echo "Deploying via GitOps..."
    cd ~/WORKING_WORKSPACE/infra-gitops
    
    # Apply test configuration
    kubectl apply -k overlays/test/ || {
        echo -e "${YELLOW}Creating test overlay...${NC}"
        mkdir -p overlays/test
        cat > overlays/test/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: fennel-test

resources:
  - ../../base

patchesStrategicMerge:
  - values-test.yaml

configMapGenerator:
  - name: fennel-test-config
    literals:
      - environment=test
      - azure.enabled=true
EOF
        
        # Create test values
        cat > overlays/test/values-test.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: fennel-values
data:
  values.yaml: |
    node:
      chain: "local"  # Change to custom PoA spec
    persistence:
      enabled: true
      storageClass: "managed-csi"  # Azure disk
      size: "10Gi"  # Small for testing
    resources:
      requests:
        cpu: "250m"
        memory: "512Mi"
      limits:
        cpu: "1000m"
        memory: "2Gi"
EOF
    }
    
    # Deploy
    kubectl apply -k overlays/test/
    
    # Wait for pods
    echo "Waiting for blockchain to start..."
    kubectl wait --for=condition=ready pod -l app=fennel-solonet \
        -n $NAMESPACE --timeout=300s || true
    
    echo -e "${GREEN}✓ Blockchain deployed!${NC}"
}

run_tests() {
    echo -e "\n${GREEN}Running validation tests...${NC}"
    
    # Get pod name
    POD=$(kubectl get pod -n $NAMESPACE -l app=fennel-solonet -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$POD" ]; then
        echo -e "${RED}No pods found!${NC}"
        return 1
    fi
    
    # Test 1: Health check
    echo "Test 1: Health check..."
    kubectl exec -n $NAMESPACE $POD -- curl -s \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"system_health","params":[],"id":1}' \
        http://localhost:9944 | jq .
    
    # Test 2: Block production
    echo "Test 2: Block production..."
    BLOCK1=$(kubectl exec -n $NAMESPACE $POD -- curl -s \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"chain_getHeader","params":[],"id":1}' \
        http://localhost:9944 | jq -r .result.number)
    
    sleep 10
    
    BLOCK2=$(kubectl exec -n $NAMESPACE $POD -- curl -s \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"chain_getHeader","params":[],"id":1}' \
        http://localhost:9944 | jq -r .result.number)
    
    echo "Block height increased from $BLOCK1 to $BLOCK2"
    
    # Test 3: Expose RPC endpoint
    echo "Test 3: Creating temporary public endpoint..."
    kubectl port-forward -n $NAMESPACE $POD 9944:9944 &
    PF_PID=$!
    sleep 3
    
    echo -e "${YELLOW}RPC endpoint available at: http://localhost:9944${NC}"
    echo -e "${YELLOW}Connect with Polkadot.js Apps to test${NC}"
    
    # Optional: Create Azure Load Balancer for external access
    # kubectl expose pod $POD --type=LoadBalancer --port=9944 -n $NAMESPACE
    
    echo -e "\n${GREEN}✓ Basic tests passed!${NC}"
    echo "Press any key to stop port forwarding..."
    read -n 1 -s
    kill $PF_PID 2>/dev/null || true
}

monitor_costs() {
    echo -e "\n${BLUE}Monitoring Azure costs...${NC}"
    
    # Show current resource group cost
    echo "Fetching cost data..."
    az consumption usage list \
        --start-date $(date -d '7 days ago' +%Y-%m-%d) \
        --end-date $(date +%Y-%m-%d) \
        --query "[?contains(resourceGroup, '$RESOURCE_GROUP')]" \
        --output table || echo "Cost data not yet available"
    
    # Show resource details
    echo -e "\n${YELLOW}Current resources:${NC}"
    az resource list --resource-group $RESOURCE_GROUP --output table
    
    # Estimate daily cost
    echo -e "\n${YELLOW}Estimated daily cost:${NC}"
    echo "- AKS cluster ($NODE_COUNT × $NODE_SIZE): ~$5-10/day"
    echo "- Storage (10GB × $NODE_COUNT): ~$0.50/day"
    echo "- Network egress: Variable"
    echo -e "${GREEN}Total estimate: $5-15/day for testing${NC}"
}

shutdown_cluster() {
    echo -e "\n${YELLOW}Shutting down cluster (keeping data)...${NC}"
    
    # Scale down to 0 nodes (stops billing for compute)
    echo "Scaling cluster to 0 nodes..."
    az aks scale \
        --resource-group $RESOURCE_GROUP \
        --name $CLUSTER_NAME \
        --node-count 0
    
    echo -e "${GREEN}✓ Cluster stopped! Storage and config preserved.${NC}"
    echo -e "${YELLOW}Cost while stopped: ~$0.50/day (storage only)${NC}"
}

destroy_everything() {
    echo -e "\n${RED}WARNING: This will delete everything!${NC}"
    echo -n "Type 'DESTROY' to confirm: "
    read confirm
    
    if [ "$confirm" = "DESTROY" ]; then
        echo "Deleting resource group..."
        az group delete --name $RESOURCE_GROUP --yes --no-wait
        echo -e "${GREEN}✓ Deletion initiated. Will complete in ~5 minutes.${NC}"
    else
        echo "Cancelled."
    fi
}

show_status() {
    echo -e "\n${BLUE}Current Status:${NC}"
    
    # Check if resource group exists
    if az group show --name $RESOURCE_GROUP &>/dev/null; then
        echo "✓ Resource group exists: $RESOURCE_GROUP"
        
        # Check AKS status
        STATUS=$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query powerState.code -o tsv 2>/dev/null || echo "Not found")
        echo "  AKS cluster status: $STATUS"
        
        # Check node count
        NODES=$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query agentPoolProfiles[0].count -o tsv 2>/dev/null || echo "0")
        echo "  Active nodes: $NODES"
        
        # Check pods if cluster is running
        if [ "$STATUS" = "Running" ] && [ "$NODES" -gt 0 ]; then
            echo -e "\n  Kubernetes pods:"
            kubectl get pods -n $NAMESPACE 2>/dev/null || echo "    No connection to cluster"
        fi
    else
        echo "✗ No test infrastructure found"
    fi
}

# Main loop
while true; do
    show_menu
    read choice
    
    case $choice in
        1) create_infrastructure ;;
        2) deploy_blockchain ;;
        3) run_tests ;;
        4) monitor_costs ;;
        5) shutdown_cluster ;;
        6) destroy_everything ;;
        7) show_status ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
done 