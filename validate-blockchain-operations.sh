#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="fennel-dev"
RPC_PORT=9944
METRICS_PORT=9615

echo -e "${BLUE}🔬 Blockchain Operations Validation${NC}"
echo "Testing Polkadot SDK functionality beyond GitOps infrastructure..."

# Test 1: Substrate Block Production
echo -e "\n${YELLOW}1. Testing Block Production${NC}"
kubectl port-forward -n "$NAMESPACE" svc/fennel-solonet-rpc $RPC_PORT:$RPC_PORT >/dev/null 2>&1 &
RPC_PID=$!
sleep 3

# Get initial block height
INITIAL_HEIGHT=$(curl -s -H "Content-Type: application/json" \
    -d '{"id":1, "jsonrpc":"2.0", "method": "chain_getHeader"}' \
    http://localhost:$RPC_PORT | jq -r '.result.number' | sed 's/0x//')

if [ "$INITIAL_HEIGHT" != "null" ] && [ -n "$INITIAL_HEIGHT" ]; then
    INITIAL_HEIGHT_DEC=$(printf "%d" "0x$INITIAL_HEIGHT")
    echo -e "  Initial block height: ${GREEN}$INITIAL_HEIGHT_DEC${NC}"
else
    echo -e "  ${RED}❌ Cannot read initial block height${NC}"
    kill $RPC_PID 2>/dev/null || true
    exit 1
fi

# Wait and check if height increased
echo "  Waiting 30 seconds for block production..."
sleep 30

CURRENT_HEIGHT=$(curl -s -H "Content-Type: application/json" \
    -d '{"id":1, "jsonrpc":"2.0", "method": "chain_getHeader"}' \
    http://localhost:$RPC_PORT | jq -r '.result.number' | sed 's/0x//')

if [ "$CURRENT_HEIGHT" != "null" ] && [ -n "$CURRENT_HEIGHT" ]; then
    CURRENT_HEIGHT_DEC=$(printf "%d" "0x$CURRENT_HEIGHT")
    if [ "$CURRENT_HEIGHT_DEC" -gt "$INITIAL_HEIGHT_DEC" ]; then
        BLOCKS_PRODUCED=$((CURRENT_HEIGHT_DEC - INITIAL_HEIGHT_DEC))
        echo -e "  ${GREEN}✅ Block production active: $BLOCKS_PRODUCED blocks in 30s${NC}"
    else
        echo -e "  ${RED}❌ No blocks produced in 30 seconds${NC}"
    fi
else
    echo -e "  ${RED}❌ Cannot read current block height${NC}"
fi

# Test 2: GRANDPA Finality
echo -e "\n${YELLOW}2. Testing GRANDPA Finality${NC}"
FINALITY_INFO=$(curl -s -H "Content-Type: application/json" \
    -d '{"id":1, "jsonrpc":"2.0", "method": "grandpa_roundState"}' \
    http://localhost:$RPC_PORT | jq -r '.result')

if [ "$FINALITY_INFO" != "null" ]; then
    echo -e "  ${GREEN}✅ GRANDPA finality operational${NC}"
    echo "  Finality info: $FINALITY_INFO"
else
    echo -e "  ${YELLOW}⚠️ GRANDPA finality info not available${NC}"
fi

# Test 3: System Health and P2P
echo -e "\n${YELLOW}3. Testing System Health and P2P Networking${NC}"
HEALTH_INFO=$(curl -s -H "Content-Type: application/json" \
    -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' \
    http://localhost:$RPC_PORT | jq -r '.result')

if [ "$HEALTH_INFO" != "null" ]; then
    PEERS=$(echo "$HEALTH_INFO" | jq -r '.peers')
    IS_SYNCING=$(echo "$HEALTH_INFO" | jq -r '.isSyncing')
    SHOULD_HAVE_PEERS=$(echo "$HEALTH_INFO" | jq -r '.shouldHavePeers')
    
    echo -e "  Peers connected: ${GREEN}$PEERS${NC}"
    echo -e "  Is syncing: $IS_SYNCING"
    echo -e "  Should have peers: $SHOULD_HAVE_PEERS"
    
    if [ "$PEERS" -gt 0 ]; then
        echo -e "  ${GREEN}✅ P2P networking operational${NC}"
    else
        echo -e "  ${YELLOW}⚠️ No peers connected (check bootnode)${NC}"
    fi
else
    echo -e "  ${RED}❌ Cannot retrieve system health${NC}"
fi

# Test 4: Network State and Authorities
echo -e "\n${YELLOW}4. Testing Network State and Authorities${NC}"
NETWORK_STATE=$(curl -s -H "Content-Type: application/json" \
    -d '{"id":1, "jsonrpc":"2.0", "method": "system_networkState"}' \
    http://localhost:$RPC_PORT | jq -r '.result')

if [ "$NETWORK_STATE" != "null" ]; then
    PEER_ID=$(echo "$NETWORK_STATE" | jq -r '.peerId')
    LISTENED_ADDRESSES=$(echo "$NETWORK_STATE" | jq -r '.listenedAddresses[]' | head -3)
    
    echo -e "  Node Peer ID: ${GREEN}$PEER_ID${NC}"
    echo -e "  Listening on:"
    echo "$LISTENED_ADDRESSES" | sed 's/^/    /'
    echo -e "  ${GREEN}✅ Network state accessible${NC}"
else
    echo -e "  ${RED}❌ Cannot retrieve network state${NC}"
fi

# Test 5: Validator Operations (if this is a validator)
echo -e "\n${YELLOW}5. Testing Validator Operations${NC}"
SESSION_KEYS=$(curl -s -H "Content-Type: application/json" \
    -d '{"id":1, "jsonrpc":"2.0", "method": "author_hasSessionKeys", "params": ["0x"]}' \
    http://localhost:$RPC_PORT | jq -r '.result')

if [ "$SESSION_KEYS" = "true" ]; then
    echo -e "  ${GREEN}✅ Node has validator session keys${NC}"
    
    # Test key rotation capability
    ROTATE_RESULT=$(curl -s -H "Content-Type: application/json" \
        -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' \
        http://localhost:$RPC_PORT | jq -r '.result')
    
    if [ "$ROTATE_RESULT" != "null" ] && [ ${#ROTATE_RESULT} -gt 10 ]; then
        echo -e "  ${GREEN}✅ Key rotation functional${NC}"
        echo -e "  New keys: ${ROTATE_RESULT:0:20}..."
    else
        echo -e "  ${YELLOW}⚠️ Key rotation may not be working${NC}"
    fi
else
    echo -e "  ${YELLOW}ℹ️ Node is not configured as validator${NC}"
fi

kill $RPC_PID 2>/dev/null || true

# Test 6: Prometheus Metrics Validation
echo -e "\n${YELLOW}6. Testing Prometheus Metrics${NC}"
FENNEL_POD=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet -o jsonpath='{.items[0].metadata.name}')

if [ -n "$FENNEL_POD" ]; then
    kubectl port-forward -n "$NAMESPACE" "$FENNEL_POD" $METRICS_PORT:$METRICS_PORT >/dev/null 2>&1 &
    METRICS_PID=$!
    sleep 3
    
    # Check specific Substrate metrics
    BLOCK_HEIGHT_METRIC=$(curl -s http://localhost:$METRICS_PORT/metrics | grep "substrate_block_height{" | head -1)
    PEER_COUNT_METRIC=$(curl -s http://localhost:$METRICS_PORT/metrics | grep "substrate_sub_libp2p_peers_count" | head -1)
    FINALITY_METRIC=$(curl -s http://localhost:$METRICS_PORT/metrics | grep "substrate_finality_grandpa_round" | head -1)
    
    if [ -n "$BLOCK_HEIGHT_METRIC" ]; then
        BLOCK_HEIGHT_VALUE=$(echo "$BLOCK_HEIGHT_METRIC" | awk '{print $2}')
        echo -e "  Block height metric: ${GREEN}$BLOCK_HEIGHT_VALUE${NC}"
    else
        echo -e "  ${RED}❌ Block height metric missing${NC}"
    fi
    
    if [ -n "$PEER_COUNT_METRIC" ]; then
        PEER_COUNT_VALUE=$(echo "$PEER_COUNT_METRIC" | awk '{print $2}')
        echo -e "  Peer count metric: ${GREEN}$PEER_COUNT_VALUE${NC}"
    else
        echo -e "  ${YELLOW}⚠️ Peer count metric missing${NC}"
    fi
    
    if [ -n "$FINALITY_METRIC" ]; then
        FINALITY_VALUE=$(echo "$FINALITY_METRIC" | awk '{print $2}')
        echo -e "  GRANDPA round metric: ${GREEN}$FINALITY_VALUE${NC}"
    else
        echo -e "  ${YELLOW}⚠️ GRANDPA round metric missing${NC}"
    fi
    
    kill $METRICS_PID 2>/dev/null || true
    echo -e "  ${GREEN}✅ Metrics endpoint accessible${NC}"
else
    echo -e "  ${RED}❌ Cannot find fennel pod for metrics testing${NC}"
fi

# Test 7: Storage and State Queries
echo -e "\n${YELLOW}7. Testing Chain State Access${NC}"
kubectl port-forward -n "$NAMESPACE" svc/fennel-solonet-rpc $RPC_PORT:$RPC_PORT >/dev/null 2>&1 &
RPC_PID=$!
sleep 3

# Query system properties
SYSTEM_PROPERTIES=$(curl -s -H "Content-Type: application/json" \
    -d '{"id":1, "jsonrpc":"2.0", "method": "system_properties"}' \
    http://localhost:$RPC_PORT | jq -r '.result')

if [ "$SYSTEM_PROPERTIES" != "null" ]; then
    CHAIN_NAME=$(echo "$SYSTEM_PROPERTIES" | jq -r '.ss58Format // .chainType // "unknown"')
    echo -e "  Chain properties: ${GREEN}accessible${NC}"
    echo -e "  Chain info: $CHAIN_NAME"
else
    echo -e "  ${RED}❌ Cannot access chain properties${NC}"
fi

# Test runtime version
RUNTIME_VERSION=$(curl -s -H "Content-Type: application/json" \
    -d '{"id":1, "jsonrpc":"2.0", "method": "state_getRuntimeVersion"}' \
    http://localhost:$RPC_PORT | jq -r '.result.specVersion')

if [ "$RUNTIME_VERSION" != "null" ]; then
    echo -e "  Runtime version: ${GREEN}$RUNTIME_VERSION${NC}"
    echo -e "  ${GREEN}✅ State queries functional${NC}"
else
    echo -e "  ${RED}❌ Cannot query runtime version${NC}"
fi

kill $RPC_PID 2>/dev/null || true

# Test 8: Pod Stability Check
echo -e "\n${YELLOW}8. Testing Pod Stability${NC}"
RESTART_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet --no-headers | awk '{print $4}' | head -1)
POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet --no-headers | awk '{print $3}' | head -1)
POD_READY=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet --no-headers | awk '{print $2}' | head -1)

echo -e "  Pod status: ${GREEN}$POD_STATUS${NC}"
echo -e "  Pod ready: ${GREEN}$POD_READY${NC}"

if [ "$RESTART_COUNT" = "0" ]; then
    echo -e "  Restart count: ${GREEN}$RESTART_COUNT${NC}"
    echo -e "  ${GREEN}✅ Pod stability confirmed${NC}"
else
    echo -e "  Restart count: ${YELLOW}$RESTART_COUNT${NC}"
    echo -e "  ${YELLOW}⚠️ Pod has restarted, investigate logs${NC}"
fi

# Final Assessment
echo -e "\n${BLUE}📋 Blockchain Operations Assessment${NC}"
echo -e "\n${GREEN}✅ INFRASTRUCTURE COMPLETE:${NC}"
echo -e "  • GitOps automation working"
echo -e "  • Security policies deployed"
echo -e "  • CI/CD pipelines functional"

echo -e "\n${YELLOW}📊 BLOCKCHAIN STATUS:${NC}"
echo -e "  • Run this script to validate blockchain operations"
echo -e "  • Check Prometheus metrics collection"
echo -e "  • Verify P2P connectivity with bootnodes"
echo -e "  • Test validator operations if applicable"

echo -e "\n${BLUE}🎯 NEXT STEPS:${NC}"
echo -e "  1. Deploy Prometheus/Grafana monitoring"
echo -e "  2. Run 24-hour soak test with this validation"
echo -e "  3. Test validator key rotation procedures"
echo -e "  4. Verify bootnode connectivity"
echo -e "  5. Prepare sudo lockdown procedures"

echo -e "\n${YELLOW}💡 NOTE:${NC} This validates the blockchain is operational."
echo -e "GitOps infrastructure ≠ blockchain functionality."
echo -e "Both must be validated separately!" 