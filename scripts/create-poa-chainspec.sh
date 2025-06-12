#!/bin/bash
# Script to create a custom PoA chain spec for Fennel network
# This replaces the dev chain (Alice/Bob) with production PoA configuration

set -e

# Configuration
FENNEL_NODE="${FENNEL_NODE:-./target/release/fennel-node}"
SUDO_ACCOUNT="${SUDO_ACCOUNT:-}"
CHAIN_NAME="${CHAIN_NAME:-Fennel PoA Network}"
CHAIN_ID="${CHAIN_ID:-fennel_poa}"
OUTPUT_DIR="${OUTPUT_DIR:-./chainspecs}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Fennel PoA Chain Spec Generator ===${NC}"
echo ""

# Check if fennel-node exists
if [ ! -f "$FENNEL_NODE" ]; then
    echo -e "${RED}Error: fennel-node binary not found at $FENNEL_NODE${NC}"
    echo "Please build the node first with: cargo build --release"
    exit 1
fi

# Check if sudo account is provided
if [ -z "$SUDO_ACCOUNT" ]; then
    echo -e "${YELLOW}Warning: No SUDO_ACCOUNT provided${NC}"
    echo "Usage: SUDO_ACCOUNT=5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY $0"
    echo ""
    echo "Using development account for testing..."
    SUDO_ACCOUNT="5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY"  # Alice for testing
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo -e "${GREEN}Step 1: Generating base chain spec...${NC}"
$FENNEL_NODE build-spec \
    --disable-default-bootnode \
    --chain local \
    > "$OUTPUT_DIR/poaSpec.json"

echo -e "${GREEN}Step 2: Modifying chain spec for PoA...${NC}"

# Create a Python script to modify the JSON
cat > "$OUTPUT_DIR/modify_spec.py" << 'EOF'
import json
import sys

# Read the chain spec
with open(sys.argv[1], 'r') as f:
    spec = json.load(f)

# Update basic properties
spec['name'] = sys.argv[2]  # Chain name
spec['id'] = sys.argv[3]     # Chain ID
spec['chainType'] = 'Live'   # Production chain

# Get sudo account
sudo_account = sys.argv[4]

# Clear bootNodes (we'll add them in deployment)
spec['bootNodes'] = []

# Modify genesis configuration
genesis = spec['genesis']['runtimeGenesis']['patch']

# Set sudo account
if 'sudo' in genesis:
    genesis['sudo']['key'] = sudo_account
else:
    genesis['sudo'] = {'key': sudo_account}

# Set up balances - give sudo account initial balance
if 'balances' in genesis:
    # Clear existing balances (removes Alice/Bob)
    genesis['balances']['balances'] = [
        [sudo_account, 1000000000000000]  # 1M units
    ]
else:
    genesis['balances'] = {
        'balances': [[sudo_account, 1000000000000000]]
    }

# Clear session keys (no initial validators)
# Validator-manager will handle this
if 'session' in genesis:
    genesis['session']['keys'] = []

# Clear Aura authorities
if 'aura' in genesis:
    genesis['aura']['authorities'] = []

# Clear Grandpa authorities  
if 'grandpa' in genesis:
    genesis['grandpa']['authorities'] = []

# Note: validator-manager pallet doesn't need genesis config
# It starts with empty state and validators are added via sudo

# Write modified spec
with open(sys.argv[1], 'w') as f:
    json.dump(spec, f, indent=2)

print(f"✓ Modified chain spec: {spec['name']} ({spec['id']})")
print(f"✓ Sudo account: {sudo_account}")
print(f"✓ Cleared dev validators (Alice/Bob)")
print(f"✓ Ready for PoA validator management")
EOF

# Run the Python script
python3 "$OUTPUT_DIR/modify_spec.py" \
    "$OUTPUT_DIR/poaSpec.json" \
    "$CHAIN_NAME" \
    "$CHAIN_ID" \
    "$SUDO_ACCOUNT"

echo -e "${GREEN}Step 3: Converting to raw format...${NC}"
$FENNEL_NODE build-spec \
    --chain="$OUTPUT_DIR/poaSpec.json" \
    --raw \
    > "$OUTPUT_DIR/poaSpecRaw.json"

# Clean up temporary files
rm -f "$OUTPUT_DIR/modify_spec.py"

echo ""
echo -e "${GREEN}=== PoA Chain Spec Generated Successfully! ===${NC}"
echo ""
echo "Files created:"
echo "  - $OUTPUT_DIR/poaSpec.json      (Human-readable)"
echo "  - $OUTPUT_DIR/poaSpecRaw.json   (Raw format for nodes)"
echo ""
echo "Key properties:"
echo "  - Chain Name: $CHAIN_NAME"
echo "  - Chain ID: $CHAIN_ID"
echo "  - Sudo Account: $SUDO_ACCOUNT"
echo "  - Initial Validators: None (add via sudo after launch)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Deploy nodes with: --chain=$OUTPUT_DIR/poaSpecRaw.json"
echo "2. Generate validator keys on each validator node"
echo "3. Use sudo to call validatorManager.registerValidators()"
echo "4. Wait 2 sessions for validators to become active"
echo ""
echo -e "${GREEN}Remember:${NC} The validator-manager pallet is already in your runtime!"
echo "This chain spec just sets up the genesis state for PoA governance." 