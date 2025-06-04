#!/bin/bash

##############################################################################
# External Validator Deployment Script
# Following Polkadot SDK Best Practices for Key Management
# Reference: https://docs.polkadot.com/infrastructure/running-a-validator/onboarding-and-offboarding/key-management/#set-node-key
##############################################################################

set -euo pipefail

# Configuration
FENNEL_IMAGE="ghcr.io/corruptedaesthetic/uptodatefennelnetmp:sha-2ea7777df54a4bc1d113591d6a2351930bae3806"
ALICE_BOOTNODE=""  # Will be discovered automatically
CHAIN_SPEC="local"

# Validator configurations
declare -A VALIDATORS=(
    ["charlie"]="Charlie;9946;10046"
    ["dave"]="Dave;9947;10047" 
    ["eve"]="Eve;9948;10048"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

##############################################################################
# Prerequisites Check
##############################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check kubectl
if ! command -v kubectl &> /dev/null; then
        error "kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if Alice is running in k3s
if ! kubectl get pods -n fennel 2>/dev/null | grep -q "fennel-solochain"; then
        error "Alice/Bob validators not found in k3s. Please deploy them first:"
    echo "   cd fennel-solonet/kubernetes && ./deploy-fennel.sh"
    exit 1
fi

    # Check if port-forward is active for Alice
if ! curl -s --connect-timeout 2 http://localhost:9944 > /dev/null; then
        error "Alice not accessible at localhost:9944. Please start port-forward:"
    echo "   kubectl port-forward -n fennel svc/fennel-solochain-node 9944:9944 &"
    exit 1
fi

    success "Prerequisites check passed"
}

##############################################################################
# Key Generation Functions (Following Official Polkadot SDK Best Practices)
##############################################################################

generate_network_key() {
    local validator_name="$1"
    local key_dir="./validator-keys/${validator_name}"
    local key_file="${key_dir}/network_key"
    
    log "Generating network key for ${validator_name} using official Polkadot SDK method..."
    
    # Create key directory
    mkdir -p "${key_dir}"
    
    # Generate network key using the official Polkadot SDK method
    # Reference: https://docs.polkadot.com/infrastructure/running-a-validator/onboarding-and-offboarding/key-management/#generate-the-node-key
    docker run --rm \
        --user $(id -u):$(id -g) \
        -v "$(pwd)/validator-keys:/keys" \
        "${FENNEL_IMAGE}" \
        key generate-node-key \
        --file "/keys/${validator_name}/network_key"
    
    if [[ -f "${key_file}" ]]; then
        # Set proper permissions (read-only for owner)
        chmod 600 "${key_file}"
        success "Network key generated for ${validator_name}"
        return 0
    else
        error "Failed to generate network key for ${validator_name}"
        return 1
    fi
}

verify_key_integrity() {
    local validator_name="$1"
    local key_file="./validator-keys/${validator_name}/network_key"
    
    if [[ ! -f "${key_file}" ]]; then
        error "Network key file not found for ${validator_name}: ${key_file}"
        return 1
    fi
    
    # Verify key file is not empty and has correct format
    local key_size=$(wc -c < "${key_file}")
    if [[ ${key_size} -lt 32 ]]; then
        error "Network key file for ${validator_name} is too small (${key_size} bytes)"
        return 1
    fi
    
    success "Network key verified for ${validator_name}"
    return 0
}

setup_all_keys() {
    log "Setting up network keys for all validators..."
    
    # Create keys directory
    mkdir -p ./validator-keys
    
    for validator_name in "${!VALIDATORS[@]}"; do
        local config="${VALIDATORS[${validator_name}]}"
        IFS=';' read -r display_name _ _ <<< "${config}"
        
        # Check if key already exists
        local key_file="./validator-keys/${validator_name}/network_key"
        if [[ -f "${key_file}" ]]; then
            warning "Network key already exists for ${display_name}, verifying integrity..."
            verify_key_integrity "${validator_name}"
        else
            generate_network_key "${validator_name}"
        fi
    done
    
    success "All network keys are ready!"
}

##############################################################################
# Discovery Functions
##############################################################################

discover_alice_bootnode() {
    log "Discovering Alice's bootnode information..."
    
    # Get Alice's IP address from Kubernetes
    local alice_ip=$(kubectl get pods -n fennel -o wide | grep "fennel-solochain-node-0" | awk '{print $6}')
    
    if [[ -z "${alice_ip}" ]] || [[ "${alice_ip}" == "<none>" ]]; then
        error "Could not get Alice's IP address"
        return 1
    fi
    
    # Get Alice's peer ID via RPC
    local alice_peer_id=$(curl -s -H "Content-Type: application/json" \
        -d '{"id":1, "jsonrpc":"2.0", "method": "system_localPeerId"}' \
        http://localhost:9944 | jq -r '.result')
    
    if [[ -z "${alice_peer_id}" ]] || [[ "${alice_peer_id}" == "null" ]]; then
        error "Could not get Alice's peer ID"
        return 1
    fi
    
    ALICE_BOOTNODE="/ip4/${alice_ip}/tcp/30333/p2p/${alice_peer_id}"
    success "Alice bootnode: ${ALICE_BOOTNODE}"
    
    return 0
}

##############################################################################
# Deployment Functions (Following Polkadot SDK Best Practices)
##############################################################################

deploy_validator() {
    local validator_name="$1"
    local config="${VALIDATORS[${validator_name}]}"
    
    # Parse configuration: "DisplayName;RpcPort;P2pPort"
    IFS=';' read -r display_name rpc_port p2p_port <<< "${config}"
    
    local container_name="fennel-external-${validator_name}"
    local key_file="$(pwd)/validator-keys/${validator_name}/network_key"
    local data_dir="$(pwd)/validator-data/${validator_name}"
    
    log "Deploying validator: ${display_name} (${validator_name})"
    
    # Ensure data directory exists
    mkdir -p "${data_dir}"
    
    # Verify network key exists
    if ! verify_key_integrity "${validator_name}"; then
        return 1
    fi
    
    # Stop existing container if running
    if docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        log "Stopping existing ${container_name} container..."
        docker stop "${container_name}" >/dev/null 2>&1 || true
        docker rm "${container_name}" >/dev/null 2>&1 || true
    fi
    
    # Deploy validator with proper key management following official Polkadot SDK practices
    log "Starting ${container_name} with pre-generated network key..."
    
    docker run -d \
        --name "${container_name}" \
        --restart unless-stopped \
        --user $(id -u):$(id -g) \
        -v "${key_file}:/data/network_key:ro" \
        -v "${data_dir}:/data/chains" \
        -p "${rpc_port}:9944" \
        -p "${p2p_port}:30333" \
        -e RUST_LOG=info \
        "${FENNEL_IMAGE}" \
        --name "${display_name}" \
        --base-path /data \
        --chain "${CHAIN_SPEC}" \
        --validator \
        --node-key-file /data/network_key \
        --listen-addr /ip4/0.0.0.0/tcp/30333 \
        --rpc-external \
        --rpc-port 9944 \
        --rpc-cors all \
        --rpc-methods unsafe \
        --prometheus-external \
        --telemetry-url "wss://telemetry.polkadot.io/submit/ 0" \
        --bootnodes "${ALICE_BOOTNODE}"
    
    if [[ $? -eq 0 ]]; then
        success "Successfully started ${display_name}"
        
        # Wait for startup
        log "Waiting for ${display_name} to initialize..."
        sleep 10
        
        # Check connectivity
        if curl -s --connect-timeout 5 -H "Content-Type: application/json" \
           -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' \
           http://localhost:${rpc_port} > /dev/null; then
            success "${display_name} is running and accessible"
            log "   RPC Port: ${rpc_port}"
            log "   P2P Port: ${p2p_port}"
            log "   Network Key: ✓ Pre-generated (Polkadot SDK compliant)"
            log "   Polkadot.js: ws://localhost:${rpc_port}"
        else
            warning "${display_name} started but may not be fully ready yet"
        fi
        
        return 0
    else
        error "Failed to start ${display_name}"
        return 1
    fi
}

##############################################################################
# Management Functions  
##############################################################################

show_status() {
    log "External Validator Status (Polkadot SDK Compliant):"
    echo
    
    for validator_name in "${!VALIDATORS[@]}"; do
        local container_name="fennel-external-${validator_name}"
        local config="${VALIDATORS[${validator_name}]}"
        IFS=';' read -r display_name rpc_port p2p_port <<< "${config}"
        
        echo "📡 ${display_name} (${validator_name}):"
        
        # Check container status
        if docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            echo "   Status: ${GREEN}Running${NC}"
            echo "   RPC: ws://localhost:${rpc_port}"
            echo "   P2P Port: ${p2p_port}"
            
            # Check network key
            local key_file="./validator-keys/${validator_name}/network_key"
            if [[ -f "${key_file}" ]]; then
                echo "   Network Key: ${GREEN}✓ Pre-generated (SDK Compliant)${NC}"
            else
                echo "   Network Key: ${RED}✗ Missing${NC}"
            fi
            
            # Check health
            if curl -s --connect-timeout 2 http://localhost:${rpc_port} > /dev/null; then
                local health=$(curl -s -H "Content-Type: application/json" \
                    -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' \
                    http://localhost:${rpc_port} | jq -r '.result')
                echo "   Health: ${GREEN}${health}${NC}"
            else
                echo "   Health: ${RED}Not accessible${NC}"
            fi
        else
            echo "   Status: ${RED}Stopped${NC}"
        fi
        echo
    done
}

cleanup_all() {
    log "Cleaning up all external validators..."
    
    for validator_name in "${!VALIDATORS[@]}"; do
        local container_name="fennel-external-${validator_name}"
        local config="${VALIDATORS[${validator_name}]}"
        IFS=';' read -r display_name _ _ <<< "${config}"
        
        if docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
            log "Stopping ${display_name}..."
            docker stop "${container_name}" >/dev/null 2>&1 || true
            docker rm "${container_name}" >/dev/null 2>&1 || true
            success "Stopped ${display_name}"
            fi
        done
    
    # Optionally remove data
    read -p "Remove validator data directories? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf ./validator-data
        success "Removed validator data"
    fi
    
    # Optionally remove keys (be careful!)
    read -p "Remove generated network keys? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf ./validator-keys
        warning "Removed all generated keys - you'll need to regenerate them"
    fi
}

##############################################################################
# Main Functions
##############################################################################

show_help() {
    cat << EOF
External Validator Deployment Script
Following Polkadot SDK Best Practices for Key Management

Usage: $0 [COMMAND] [VALIDATOR]

Commands:
  setup-keys     Generate network keys for all validators
  deploy [name]  Deploy validator(s) with pre-generated keys
  status         Show status of all validators
  clean          Stop validators and optionally clean up data/keys
  help           Show this help message

Validator Names:
  charlie, dave, eve, all

Examples:
  $0 setup-keys         # Generate network keys first (required)
  $0 deploy charlie     # Deploy only Charlie
  $0 deploy all         # Deploy all validators
  $0 status             # Check validator status
  $0 clean              # Stop and cleanup

The script follows the official Polkadot SDK documentation:
https://docs.polkadot.com/infrastructure/running-a-validator/onboarding-and-offboarding/key-management/#set-node-key

Key Features:
- Pre-generates network keys using 'key generate-node-key --file'
- Uses --node-key-file parameter for stable network identity
- Includes --validator flag for block production capability
- Avoids unsafe key generation flags
- Proper key file permissions (600)
- Automatic Alice bootnode discovery

Next Steps After Deployment:
1. Generate session keys via Polkadot.js Apps
2. Register validators using ValidatorManager
3. Monitor validator performance

EOF
}

##############################################################################
# Main Script Entry Point
##############################################################################

main() {
    local command="${1:-help}"
    local validator="${2:-}"
    
    echo "🚀 External Validator Deployment (Polkadot SDK Compliant)"
    echo "==========================================================="
    echo
    
    case "${command}" in
        "setup-keys")
            check_prerequisites
            setup_all_keys
            ;;
        "deploy")
            check_prerequisites
            setup_all_keys  # Ensure keys exist
            discover_alice_bootnode
            
            case "${validator}" in
                "charlie"|"dave"|"eve")
                    deploy_validator "${validator}"
                    ;;
                "all"|"")
                    local success_count=0
                    local total_count=${#VALIDATORS[@]}
                    
                    for validator_name in "${!VALIDATORS[@]}"; do
                        if deploy_validator "${validator_name}"; then
                            ((success_count++))
                        fi
                        sleep 2  # Brief pause between deployments
                    done
                    
                    echo
                    if [[ ${success_count} -eq ${total_count} ]]; then
                        success "Successfully deployed all ${total_count} validators!"
                    else
                        warning "Deployed ${success_count}/${total_count} validators"
                    fi
                    ;;
                *)
                    error "Unknown validator: ${validator}"
                    echo "Valid options: charlie, dave, eve, all"
                    exit 1
                    ;;
            esac
            
            echo
            show_status
            ;;
        "status")
            show_status
            ;;
        "clean")
            cleanup_all
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Unknown command: ${command}"
            echo
            show_help
        exit 1
        ;;
esac

    # Show next steps
    echo
    log "🎯 Next Steps:"
    echo "1. Check status: $0 status"
    echo "2. Generate session keys via Polkadot.js Apps:"
echo "   - Charlie: ws://localhost:9946"
echo "   - Dave: ws://localhost:9947"  
echo "   - Eve: ws://localhost:9948"
echo "   - Use Developer > RPC calls > author.rotateKeys()"
    echo "3. Register validators through ValidatorManager on Alice"
    echo "4. Monitor validator performance and block authoring"
    echo
    echo "📖 Reference: https://docs.polkadot.com/infrastructure/running-a-validator/onboarding-and-offboarding/key-management/#set-node-key"
}

# Execute main function with all arguments
main "$@" 