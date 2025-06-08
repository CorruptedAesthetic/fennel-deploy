#!/bin/bash

# 🧹 FENNEL DEPLOY - ENVIRONMENT CLEANUP SCRIPT
# ===============================================================================
# ⚠️  WARNING: This script performs DESTRUCTIVE OPERATIONS on LOCAL environments!
# 🚨 This will PERMANENTLY DELETE all blockchain data, deployments, and state!
# 
# For production environments, use proper CI/CD pipelines and never run cleanup.
# ===============================================================================
# 
# This dedicated cleanup script provides:
# - Quick cleanup (recommended for testing)
# - Complete cleanup (includes k3s uninstall)
# 
# USAGE: ./cleanup-environment.sh [quick|complete|help]
# ===============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
WORKSPACE_DIR="/home/neurosx/WORKING_WORKSPACE/fennel-deploy"
K8S_DIR="$WORKSPACE_DIR/fennel-solonet/kubernetes"

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅${NC} $1"
}

log_substep() {
    local message="$1"
    local status="${2:-WORKING}"
    local timestamp=$(date '+%H:%M:%S')
    
    case $status in
        "SUCCESS")
            echo -e "${GREEN}  ✅ [$timestamp] $message${NC}"
            ;;
        "WORKING")
            echo -e "${YELLOW}  ⏳ [$timestamp] $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}  ❌ [$timestamp] $message${NC}"
            ;;
        *)
            echo -e "${BLUE}  ℹ️  [$timestamp] $message${NC}"
            ;;
    esac
}

# Simple safety check for local environments
check_local_environment() {
    local context=$(kubectl config current-context 2>/dev/null || echo "local")
    
    # Basic production environment check
    if [[ "$context" == *"prod"* ]] || [[ "$context" == *"production"* ]]; then
        echo -e "${RED}❌ Production environment detected - cleanup blocked!${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}💻 Local environment detected: $context${NC}"
}

# Quick cleanup for daily testing (no confirmation required)
quick_cleanup() {
    check_local_environment
    
    echo ""
    echo -e "${YELLOW}🧹 QUICK CLEANUP FOR DAILY TESTING${NC}"
    echo -e "${YELLOW}═════════════════════════════════${NC}"
    echo -e "${CYAN}Fast cleanup of fennel services and deployments...${NC}"
    echo ""
    
    log "🧹 Starting quick cleanup..."
    
    cd "$WORKSPACE_DIR"
    
    # Stop services
    log_substep "Stopping Docker Compose services..." "WORKING"
    docker-compose down 2>/dev/null || true
    docker-compose -f docker-compose.apps.yml down 2>/dev/null || true
    
    # Kill port forwards
    log_substep "Stopping port forwards..." "WORKING"
    pkill -f "kubectl port-forward" 2>/dev/null || true
    tmux kill-server 2>/dev/null || true
    
    # Clean k3s deployments
    log_substep "Removing k3s deployments..." "WORKING"
    cd "$K8S_DIR" 2>/dev/null || true
    helm uninstall fennel-solochain -n fennel 2>/dev/null || true
    helm uninstall fennel-bootnodes -n fennel 2>/dev/null || true
    kubectl delete namespace fennel --ignore-not-found=true 2>/dev/null || true
    
    # Clean external validators
    log_substep "Stopping external validators..." "WORKING"
    docker stop $(docker ps -aq --filter name=fennel-external) 2>/dev/null || true
    docker rm $(docker ps -aq --filter name=fennel-external) 2>/dev/null || true
    sudo rm -rf /tmp/fennel-external-* 2>/dev/null || true
    
    # Clean Docker volumes
    log_substep "Cleaning Docker volumes..." "WORKING"
    docker volume ls -q | grep -i fennel | xargs -r docker volume rm 2>/dev/null || true
    
    # Note: Grafana cleanup removed - WhiteFlag app now uses port 3001 to avoid conflicts
    log_substep "No service conflicts - WhiteFlag app uses port 3001" "SUCCESS"
    
    sleep 3
    
    log_success "Quick cleanup complete - environment ready for fresh deployment"
}



# Show help
show_help() {
    echo ""
    echo -e "${CYAN}🧹 FENNEL DAILY CLEANUP SCRIPT${NC}"
    echo -e "${CYAN}═══════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}📋 Purpose: Fast cleanup for daily testing and development${NC}"
    echo ""
    echo -e "${BLUE}USAGE:${NC}"
    echo "  ./cleanup-environment.sh [quick|help]"
    echo ""
    echo -e "${BLUE}OPTIONS:${NC}"
    echo "  quick      🧹 Quick cleanup (services, deployments, containers) - DEFAULT"
    echo "  help       📖 Show this help message"
    echo ""
    echo -e "${GREEN}RECOMMENDED WORKFLOW:${NC}"
    echo "  1. ./cleanup-environment.sh quick           # Clean environment"
    echo "  2. ./deploy-scenario2.sh alice-bob         # Deploy fresh"
    echo ""
    echo -e "${YELLOW}FOR COMPLETE SYSTEM RESET:${NC}"
    echo "  Use: ./comprehensive-cleanup.sh             # Nuclear option"
    echo ""
    echo -e "${GREEN}💡 This script is optimized for fast, daily testing cleanup!${NC}"
}

# Main execution
main() {
    local action="${1:-quick}"
    
    case "$action" in
        "quick"|"")
            quick_cleanup
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $action${NC}"
            echo -e "${YELLOW}Available options: quick, help${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Execute main function
main "$@" 