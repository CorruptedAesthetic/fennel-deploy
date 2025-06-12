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
INTERVAL=300  # 5 minutes
DURATION=86400  # 24 hours
LOG_FILE="soak-test-$(date +%Y%m%d-%H%M%S).log"
METRICS_FILE="metrics-$(date +%Y%m%d-%H%M%S).csv"

echo -e "${BLUE}🕐 Starting 24-Hour Soak Test for Polkadot SDK GitOps${NC}"
echo "Monitoring namespace: $NAMESPACE"
echo "Check interval: ${INTERVAL}s ($(($INTERVAL/60)) minutes)"
echo "Duration: ${DURATION}s (24 hours)"
echo "Log file: $LOG_FILE"
echo "Metrics file: $METRICS_FILE"

# Initialize metrics CSV
echo "timestamp,pods_ready,pods_total,peer_count,block_height,rpc_responsive,memory_usage_mb,cpu_usage_percent,restart_count,flux_healthy" > "$METRICS_FILE"

# Trap to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up background processes...${NC}"
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 0
}
trap cleanup EXIT INT TERM

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check pod health
check_pod_health() {
    local ready_pods=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet --no-headers 2>/dev/null | grep "Running" | grep "1/1" | wc -l || echo "0")
    local total_pods=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet --no-headers 2>/dev/null | wc -l || echo "0")
    echo "$ready_pods,$total_pods"
}

# Function to get peer count
get_peer_count() {
    local fennel_pod=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$fennel_pod" ]; then
        local peer_count=$(kubectl logs -n "$NAMESPACE" "$fennel_pod" --tail=50 2>/dev/null | grep -o '[0-9]\+ peers' | tail -1 | cut -d' ' -f1 || echo "0")
        echo "$peer_count"
    else
        echo "0"
    fi
}

# Function to get block height
get_block_height() {
    # Port forward and test RPC (run in background, get result, cleanup)
    kubectl port-forward -n "$NAMESPACE" svc/fennel-solonet-rpc 9944:9944 >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 2
    
    local block_height=$(curl -s -H "Content-Type: application/json" \
        -d '{"id":1, "jsonrpc":"2.0", "method": "chain_getHeader"}' \
        http://localhost:9944 2>/dev/null | jq -r '.result.number' 2>/dev/null | sed 's/0x//' || echo "0")
    
    kill $pf_pid 2>/dev/null || true
    
    if [ "$block_height" != "0" ] && [ "$block_height" != "null" ]; then
        printf "%d" "0x$block_height" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to test RPC responsiveness
test_rpc_health() {
    kubectl port-forward -n "$NAMESPACE" svc/fennel-solonet-rpc 9944:9944 >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 2
    
    local health=$(curl -s -H "Content-Type: application/json" \
        -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' \
        http://localhost:9944 2>/dev/null | jq -r '.result.shouldHavePeers' 2>/dev/null || echo "false")
    
    kill $pf_pid 2>/dev/null || true
    
    if [ "$health" = "true" ]; then
        echo "1"
    else
        echo "0"
    fi
}

# Function to get resource usage
get_resource_usage() {
    local fennel_pod=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$fennel_pod" ]; then
        local metrics=$(kubectl top pod -n "$NAMESPACE" "$fennel_pod" --no-headers 2>/dev/null || echo "0m 0Mi")
        local cpu=$(echo "$metrics" | awk '{print $2}' | sed 's/m//' || echo "0")
        local memory=$(echo "$metrics" | awk '{print $3}' | sed 's/Mi//' || echo "0")
        echo "$memory,$cpu"
    else
        echo "0,0"
    fi
}

# Function to get restart count
get_restart_count() {
    local restart_count=$(kubectl get pods -n "$NAMESPACE" -l app=fennel-solonet --no-headers 2>/dev/null | awk '{print $4}' | head -1 || echo "0")
    echo "$restart_count"
}

# Function to check Flux health
check_flux_health() {
    if command -v flux &> /dev/null; then
        local flux_status=$(flux check --pre 2>/dev/null && echo "1" || echo "0")
        echo "$flux_status"
    else
        # Fallback: check if flux-system pods are running
        local flux_pods=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
        if [ "$flux_pods" -gt 0 ]; then
            echo "1"
        else
            echo "0"
        fi
    fi
}

# Function to generate health report
generate_health_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local pods_health=$(check_pod_health)
    local peer_count=$(get_peer_count)
    local block_height=$(get_block_height)
    local rpc_health=$(test_rpc_health)
    local resource_usage=$(get_resource_usage)
    local restart_count=$(get_restart_count)
    local flux_health=$(check_flux_health)
    
    # Parse values
    local ready_pods=$(echo "$pods_health" | cut -d',' -f1)
    local total_pods=$(echo "$pods_health" | cut -d',' -f2)
    local memory_usage=$(echo "$resource_usage" | cut -d',' -f1)
    local cpu_usage=$(echo "$resource_usage" | cut -d',' -f2)
    
    # Log to CSV
    echo "$timestamp,$ready_pods,$total_pods,$peer_count,$block_height,$rpc_health,$memory_usage,$cpu_usage,$restart_count,$flux_health" >> "$METRICS_FILE"
    
    # Console output
    echo -e "\n${BLUE}📊 Health Check @ $timestamp${NC}"
    
    if [ "$ready_pods" = "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
        echo -e "  Pods: ${GREEN}$ready_pods/$total_pods Ready${NC}"
    else
        echo -e "  Pods: ${RED}$ready_pods/$total_pods Ready${NC}"
    fi
    
    if [ "$peer_count" -gt 0 ]; then
        echo -e "  P2P: ${GREEN}$peer_count peers connected${NC}"
    else
        echo -e "  P2P: ${YELLOW}$peer_count peers connected${NC}"
    fi
    
    if [ "$block_height" -gt 0 ]; then
        echo -e "  Chain: ${GREEN}Block height $block_height${NC}"
    else
        echo -e "  Chain: ${YELLOW}Block height $block_height${NC}"
    fi
    
    if [ "$rpc_health" = "1" ]; then
        echo -e "  RPC: ${GREEN}Responsive${NC}"
    else
        echo -e "  RPC: ${RED}Not responding${NC}"
    fi
    
    echo -e "  Resources: ${YELLOW}${memory_usage}Mi memory, ${cpu_usage}m CPU${NC}"
    
    if [ "$restart_count" = "0" ]; then
        echo -e "  Stability: ${GREEN}No restarts${NC}"
    else
        echo -e "  Stability: ${YELLOW}$restart_count restarts${NC}"
    fi
    
    if [ "$flux_health" = "1" ]; then
        echo -e "  GitOps: ${GREEN}Flux healthy${NC}"
    else
        echo -e "  GitOps: ${RED}Flux issues detected${NC}"
    fi
}

# Function to analyze trends
analyze_trends() {
    if [ -f "$METRICS_FILE" ]; then
        local total_checks=$(tail -n +2 "$METRICS_FILE" | wc -l)
        local successful_checks=$(tail -n +2 "$METRICS_FILE" | awk -F',' '$2==$3 && $3>0 && $5==1' | wc -l)
        local uptime_percent=$((successful_checks * 100 / total_checks))
        
        echo -e "\n${BLUE}📈 Trend Analysis${NC}"
        echo -e "  Total checks: $total_checks"
        echo -e "  Successful: $successful_checks"
        
        if [ "$uptime_percent" -ge 95 ]; then
            echo -e "  Uptime: ${GREEN}${uptime_percent}%${NC}"
        elif [ "$uptime_percent" -ge 90 ]; then
            echo -e "  Uptime: ${YELLOW}${uptime_percent}%${NC}"
        else
            echo -e "  Uptime: ${RED}${uptime_percent}%${NC}"
        fi
        
        # Get average peer count
        local avg_peers=$(tail -n +2 "$METRICS_FILE" | awk -F',' '{sum+=$4; count++} END {if(count>0) print int(sum/count); else print 0}')
        echo -e "  Average peers: $avg_peers"
        
        # Check for restarts
        local max_restarts=$(tail -n +2 "$METRICS_FILE" | awk -F',' '{if($9>max) max=$9} END {print max+0}')
        if [ "$max_restarts" = "0" ]; then
            echo -e "  Restarts: ${GREEN}None detected${NC}"
        else
            echo -e "  Restarts: ${YELLOW}Max $max_restarts${NC}"
        fi
    fi
}

# Function to check for issues
check_for_issues() {
    log "Starting 24-hour soak test monitoring..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + DURATION))
    local check_count=0
    local issue_count=0
    
    while [ $(date +%s) -lt $end_time ]; do
        check_count=$((check_count + 1))
        
        # Generate health report
        generate_health_report
        
        # Check for critical issues
        local pods_health=$(check_pod_health)
        local ready_pods=$(echo "$pods_health" | cut -d',' -f1)
        local total_pods=$(echo "$pods_health" | cut -d',' -f2)
        
        if [ "$ready_pods" != "$total_pods" ] || [ "$total_pods" = "0" ]; then
            issue_count=$((issue_count + 1))
            log "❌ ISSUE: Pod health problem - $ready_pods/$total_pods ready"
        fi
        
        local rpc_health=$(test_rpc_health)
        if [ "$rpc_health" = "0" ]; then
            issue_count=$((issue_count + 1))
            log "❌ ISSUE: RPC endpoint not responding"
        fi
        
        # Show progress
        local elapsed=$(($(date +%s) - start_time))
        local progress=$((elapsed * 100 / DURATION))
        local remaining=$((DURATION - elapsed))
        local remaining_hours=$((remaining / 3600))
        local remaining_minutes=$(((remaining % 3600) / 60))
        
        echo -e "  Progress: ${YELLOW}${progress}% complete${NC} - ${remaining_hours}h ${remaining_minutes}m remaining"
        
        # Periodic trend analysis
        if [ $((check_count % 12)) = 0 ]; then  # Every hour
            analyze_trends
        fi
        
        # Sleep until next check
        sleep $INTERVAL
    done
    
    # Final report
    echo -e "\n${GREEN}🎉 24-Hour Soak Test Complete!${NC}"
    log "Soak test completed - $check_count checks performed, $issue_count issues detected"
    
    analyze_trends
    
    # Generate final summary
    echo -e "\n${BLUE}📋 Final Summary${NC}"
    if [ "$issue_count" = "0" ]; then
        echo -e "  Result: ${GREEN}✅ PASS - No critical issues detected${NC}"
        echo -e "  Ready for: ${GREEN}Production promotion (Step 10)${NC}"
    elif [ "$issue_count" -lt 5 ]; then
        echo -e "  Result: ${YELLOW}⚠️ CONDITIONAL PASS - Minor issues detected${NC}"
        echo -e "  Action: Review logs and consider fixes before promotion"
    else
        echo -e "  Result: ${RED}❌ FAIL - Multiple issues detected${NC}"
        echo -e "  Action: Investigate and resolve issues before retesting"
    fi
    
    echo -e "\n📁 Files generated:"
    echo -e "  📝 Detailed log: $LOG_FILE"
    echo -e "  📊 Metrics data: $METRICS_FILE"
    echo -e "\nNext steps:"
    echo -e "  1. Review generated reports"
    echo -e "  2. Address any identified issues"
    echo -e "  3. Update PROGRESS.md with results"
    echo -e "  4. Proceed to staging promotion if successful"
}

# Start monitoring
check_for_issues 