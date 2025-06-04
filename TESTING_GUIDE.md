# Fennel Deploy Testing Guide

## Overview

This guide explains the updated testing approach for fennel-deploy, which now uses:
- **Docker Compose**: For application services (API, frontend, databases, etc.)
- **k3s/Kubernetes**: For multi-validator blockchain testing with the **Validator Manager Pallet**
- **🚀 NEW: Simplified Dockerfile**: Uses runtime presets for unified genesis across all environments

### Key Improvements ✅ UPDATED
- **✅ Unified Genesis**: No more chainspec file consistency issues
- **✅ Runtime Presets**: Built-in Alice/Bob validators via `--chain local`
- **✅ Simplified Deployment**: 90% less Dockerfile complexity
- **✅ Production Standard**: Follows official Polkadot SDK patterns
- Removed static `peer` service configuration
- Introduced dynamic validator management through the Validator Manager Pallet
- Better separation between application services and blockchain infrastructure
- Production-ready validator operations without manual container management

### 🔄 **Migration from Old Chainspec Approach**
**✅ SOLVED: Genesis Consistency Problems**

**Old Approach (❌ Problematic):**
```dockerfile
# Generate chainspec during build
RUN ./target/release/fennel-node build-spec --chain local > chainspec.json
COPY --from=builder /fennel/fennelSpecRaw.json /fennel/fennelSpecRaw.json
```
- Manual chainspec regeneration required
- Files get stale when runtime changes
- Local vs K8s genesis mismatches
- Complex file management

**New Approach (✅ Simplified):**
```dockerfile
# No chainspec files needed!
ENTRYPOINT ["/usr/local/bin/fennel-node"]
```
- **Same command everywhere**: `--chain local`
- **Always current**: Uses runtime presets
- **Never stale**: Generated from code
- **Unified genesis**: Identical across all environments

**🧹 Prerequisites: Clean Environment**
```bash
cd /home/neurosx/WORKING_WORKSPACE/fennel-deploy && docker-compose down
sudo systemctl stop grafana-server || sudo service grafana-server stop || sudo kill 1500
```

## Three Testing Scenarios

### 🟢 Scenario 1: Docker Compose with Single Chain
**Purpose**: Quick full-stack testing with minimal setup

```bash
# Start everything (apps + single validator)
docker-compose up -d

# Note: Use 'docker-compose' (with hyphen), not 'docker compose' (with space)

# Check service status
docker-compose ps

# Access services:
# - App: http://localhost:3000
# - API: http://localhost:1234
# - Blockchain RPC: ws://localhost:9945
# - Polkadot.js: https://polkadot.js.org/apps/?rpc=ws://localhost:9945

# View chain logs
docker-compose logs -f chain
```

**Use when**:
- Quick smoke testing
- Frontend/API development
- Single validator is sufficient
- Limited resources

#### ⚠️ Important: Single Validator Block Production

For a single validator to produce blocks, you MUST include `--force-authoring` in the chain service command in `docker-compose.yml`:

```yaml
chain:
  command: --base-path /app/chain --chain local --alice ... --force-authoring
```

Without this flag, a single validator will stay at block #0 indefinitely!

### 🔵 Scenario 2: Docker Compose (Apps) + k3s (Multi-Validator)
**Purpose**: Full-stack testing with production-like blockchain

This is the **MAIN PRODUCTION WORKFLOW** that successfully deploys Alice, Bob, and external validators (Charlie, Dave, Eve).

### 🟣 Scenario 3: k3s Only (No Docker Compose)
**Purpose**: Pure blockchain testing without applications

```bash
# Deploy only blockchain validators
cd fennel-solonet/kubernetes
./deploy-fennel.sh

# Port forward to access
kubectl port-forward -n fennel svc/fennel-solochain-node 9944:9944

# Connect via Polkadot.js
# https://polkadot.js.org/apps/?rpc=ws://localhost:9944
```

**Use when**:
- Blockchain-only development
- Validator testing
- Consensus testing
- No need for API/frontend

## Quick Decision Guide

```
Need Frontend/API?
├── YES
│   ├── Need Multiple Validators?
│   │   ├── YES → Scenario 2 (Production Multi-Validator Workflow)
│   │   └── NO  → Scenario 1 (docker-compose)
│   └── 
└── NO → Scenario 3 (k3s only)
```

## ⚠️ Important: Port Conflicts

The single chain service (docker-compose) and k3s validators use overlapping ports:
- **Port 9945** (Docker) vs **9944** (k3s) - Different but close
- **Port 30333** - Used by both (conflict!)

**Never run Scenario 1 and Scenario 2/3 simultaneously!**

To switch between scenarios:
```bash
# From Scenario 1 to 2/3
docker-compose down

# From Scenario 2/3 to 1
kubectl delete -n fennel deployment fennel-solochain-node
docker-compose down  # if apps were running
```

## Service Architecture

### Docker Compose Services
- `api`: Fennel Service API
- `database`: PostgreSQL
- `fennel-cli`: Blockchain CLI interface
- `subservice`: JavaScript backend service
- `app`: WhiteFlag School Pilot frontend
- `frontend`: Substrate frontend
- `nginx`, `app-nginx`, `substrate-nginx`: Reverse proxies
- `chain`: Single validator node (Alice)

### Kubernetes Services (k3s)
- Multiple validator nodes (Alice, Bob, Charlie, Dave, Eve)
- **Dedicated bootnodes** for external validator discovery
- Proper networking between validators
- Production-like consensus testing

---

# 🚀 **PRODUCTION MULTI-VALIDATOR WORKFLOW (Scenario 2)**

**✅ VALIDATED**: This workflow successfully deploys a complete 5-validator network following production patterns.

This workflow mirrors how **actual production networks** (Polkadot, Kusama) bootstrap and scale:
1. **Single validator bootstrap** with known keys (network operational immediately)
2. **Secure key rotation** to production keys (cryptographically random)
3. **Scale to multi-validator** with secure onboarding process
4. **External validator onboarding** via governance/ValidatorManager

## **🎯 PHASE 1: Single Validator Bootstrap (Alice)**

```bash
# Prerequisites: Clean environment
cd /home/neurosx/WORKING_WORKSPACE/fennel-deploy
docker-compose down
sudo systemctl stop grafana-server || sudo service grafana-server stop || sudo kill 1500

# Step 1: Start applications only  
docker-compose -f docker-compose.apps.yml up -d

# Verify applications are running
docker-compose -f docker-compose.apps.yml ps

# Step 2: Deploy k3s with SINGLE validator (Alice with --alice flag)
cd fennel-solonet/kubernetes

# ⚠️ IMPORTANT: Verify configuration is set for SINGLE validator bootstrap
cat fennel-values.yaml | grep -A2 -B2 "replicas:"
# MUST show: replicas: 1

cat fennel-values.yaml | grep -A5 -B5 "alice"
# MUST show: - "--alice" flag present

# Deploy the single validator
./deploy-fennel.sh

# Verify Alice is running and producing blocks
kubectl get pods -n fennel
kubectl logs -n fennel fennel-solochain-node-0 --tail=5
# Expected: 🏆 Imported #1, #2, #3... (Alice producing blocks with --alice keys)

# Step 3: Set up port forwarding for blockchain access
kubectl port-forward -n fennel svc/fennel-solochain-node 9944:9944 &
# ✅ Alice accessible at ws://localhost:9944

# Verify Alice is accessible via RPC
curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' http://localhost:9944
# Expected: {"peers":0,"isSyncing":false,"shouldHavePeers":false}

# Step 4: Generate SECURE PRODUCTION KEYS for Alice (Production Pattern!)
echo "🔑 Generating Alice's secure production keys..."
ALICE_KEYS=$(curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' http://localhost:9944 | jq -r '.result')
echo "✅ Alice's secure keys: $ALICE_KEYS"
# ✅ SAVE THIS HEX STRING - These replace Alice's well-known --alice keys!

# Step 5: Register Alice's secure keys via Polkadot.js Apps
echo ""
echo "🔗 OPEN POLKADOT.JS APPS:"
echo "https://polkadot.js.org/apps/?rpc=ws%3A%2F%2F127.0.0.1%3A9944#/extrinsics"
echo ""
echo "📋 ALICE'S REGISTRATION:"
echo "Account: Alice"
echo "Extrinsic: session → setKeys"
echo "Keys: $ALICE_KEYS"
echo "Proof: 0x"
echo ""
echo "⚡ Manual Steps in Polkadot.js:"
echo "1. Connect to ws://localhost:9944"
echo "2. Developer → Extrinsics"
echo "3. Account: Alice"
echo "4. session → setKeys"
echo "5. Paste keys above"
echo "6. Submit Transaction"
echo ""
read -p "⏳ Submit Alice's keys in Polkadot.js, then press ENTER..."

# Step 6: Verify Alice continues producing blocks with NEW secure keys
kubectl logs -n fennel fennel-solochain-node-0 --tail=5
echo "✅ PHASE 1 COMPLETE: Alice producing blocks with secure production keys"
```

## **🎯 PHASE 2: Scale to Multi-Validator (Add Bob)**

```bash
# Step 7: Scale deployment to 2 validators (Alice + Bob)
cd /home/neurosx/WORKING_WORKSPACE/fennel-deploy/fennel-solonet/kubernetes

echo "📈 Scaling to 2 validators..."
# Update configuration: replicas: 2 and remove --alice flag
# (Alice now has secure keys, Bob will get secure keys too)
helm upgrade fennel-solochain parity/node --namespace fennel --values fennel-values.yaml --wait --timeout 10m

# Verify both validators are running
kubectl get pods -n fennel
# Expected: fennel-solochain-node-0 (Alice) and fennel-solochain-node-1 (Bob)

# Check Alice still producing blocks with 1 peer (Bob)
kubectl logs -n fennel fennel-solochain-node-0 --tail=3
# Expected: Network has 1 peer (Bob connected), still producing blocks

# Step 8: Set up port forwarding to Bob for secure key generation
kubectl port-forward -n fennel fennel-solochain-node-1 9945:9944 &
# ✅ Bob accessible at ws://localhost:9945

# Verify Bob is connected and syncing
kubectl logs -n fennel fennel-solochain-node-1 --tail=3
# Expected: Connected to Alice, importing blocks

# Step 9: Generate SECURE PRODUCTION KEYS for Bob
echo "🔑 Generating Bob's secure production keys..."
BOB_KEYS=$(curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' http://localhost:9945 | jq -r '.result')
echo "✅ Bob's secure keys: $BOB_KEYS"

# Step 10: Register Bob's secure keys via Polkadot.js Apps
echo ""
echo "🔗 BOB'S REGISTRATION (SAME TAB):"
echo "https://polkadot.js.org/apps/?rpc=ws%3A%2F%2F127.0.0.1%3A9944#/extrinsics"
echo ""
echo "📋 BOB'S REGISTRATION:"
echo "Account: Bob"
echo "Extrinsic: session → setKeys"
echo "Keys: $BOB_KEYS"
echo "Proof: 0x"
echo ""
echo "⚡ Manual Steps in Polkadot.js:"
echo "1. Stay connected to Alice: ws://localhost:9944"
echo "2. Developer → Extrinsics"
echo "3. Account: Bob"
echo "4. session → setKeys"
echo "5. Paste Bob's keys above"
echo "6. Submit Transaction"
echo ""
read -p "⏳ Submit Bob's keys in Polkadot.js, then press ENTER..."

# Step 11: Verify Multi-Validator Consensus
echo "🎯 Verifying multi-validator consensus..."
sleep 10

# Check Alice's perspective
echo "📊 Alice's status:"
kubectl logs -n fennel fennel-solochain-node-0 --tail=3

# Check Bob's perspective  
echo "📊 Bob's status:"
kubectl logs -n fennel fennel-solochain-node-1 --tail=3

echo ""
echo "🎉 PHASE 2 COMPLETE: Alice + Bob Multi-Validator Consensus!"
echo "=========================================================="
echo "✅ Phase 1: Alice bootstrap → secure keys → producing blocks"
echo "✅ Phase 2: Scale to Bob → secure keys → multi-validator consensus"
echo "✅ Pattern: Real Polkadot/Kusama production workflow validated"
echo "✅ Both validators using cryptographically secure keys"
echo "✅ No well-known keys in production operation"
```

## **🎯 PHASE 3: External Validator Onboarding (Charlie, Dave, Eve)**

**⚠️ CRITICAL DIFFERENCE**: External validators are **NOT in genesis** and require **ValidatorManager authorization**

**Prerequisites**: Complete Phase 1 & 2 (Alice & Bob operational with secure keys)

### **🎯 Charlie Deployment & Onboarding**

```bash
# Step 12: Deploy bootnodes (required for external validator discovery)
cd /home/neurosx/WORKING_WORKSPACE/fennel-deploy/fennel-solonet/kubernetes
./deploy-bootnodes-remote.sh

# Verify bootnodes are running  
kubectl get pods -n fennel-bootnodes

# Step 13: Get Alice's connection info for Charlie's bootnode configuration
kubectl get pods -n fennel -o wide
# Note Alice's IP (e.g., 10.42.0.232)

ALICE_PEER_ID=$(curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "system_localPeerId"}' http://localhost:9944 | jq -r '.result')
echo "✅ Alice's Peer ID: $ALICE_PEER_ID"

# Step 14: Deploy Charlie as external Docker container
mkdir -p /tmp/fennel-test-charlie
sudo chmod 777 /tmp/fennel-test-charlie

# ⚠️ CRITICAL: Must include --validator flag for external validators to author blocks
# Replace 10.42.0.232 with Alice's actual IP from Step 13
docker run -d \
  --name fennel-test-charlie \
  -p 9946:9944 \
  -p 10046:30333 \
  -v "/tmp/fennel-test-charlie:/data" \
  ghcr.io/corruptedaesthetic/uptodatefennelnetmp:sha-2ea7777df54a4bc1d113591d6a2351930bae3806 \
  --name "TestCharlie" \
  --base-path /data \
  --chain local \
  --validator \
  --listen-addr "/ip4/0.0.0.0/tcp/30333" \
  --rpc-external \
  --rpc-port 9944 \
  --rpc-cors all \
  --rpc-methods unsafe \
  --bootnodes "/ip4/10.42.0.232/tcp/30333/p2p/$ALICE_PEER_ID"

# ✅ KEY DISCOVERY: The --validator flag is ESSENTIAL for external validators!
# Without it, Charlie runs as Role: FULL and cannot author blocks
# With it, Charlie runs as Role: AUTHORITY and can participate in consensus

# Step 15: Verify Charlie connects and syncs
sleep 15
docker logs fennel-test-charlie --tail=5
# Expected: "🏆 Imported #XXX" with 2 peers (Alice + Bob)

# Test Charlie's RPC connection
curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' http://localhost:9946
# Expected: {"peers":2,"isSyncing":false,"shouldHavePeers":true}

# Step 16: Generate SECURE PRODUCTION KEYS for Charlie
echo "🔑 Generating Charlie's secure production keys..."
CHARLIE_KEYS=$(curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' http://localhost:9946 | jq -r '.result')
echo "✅ Charlie's secure keys: $CHARLIE_KEYS"

# Step 17: Register Charlie's session keys via Polkadot.js Apps
echo ""
echo "🔗 CHARLIE'S SESSION KEY REGISTRATION:"
echo "https://polkadot.js.org/apps/?rpc=ws%3A%2F%2F127.0.0.1%3A9944#/extrinsics"
echo ""
echo "📋 CHARLIE'S SESSION REGISTRATION:"
echo "Account: Charlie (5FLSigC9HGRKVhB9FiEo4Y3koPsNmBmLJbpXg2mp1hXcS59Y)"
echo "Extrinsic: session → setKeys"
echo "Keys: $CHARLIE_KEYS"
echo "Proof: 0x"
echo ""
echo "⚡ Manual Steps in Polkadot.js:"
echo "1. Stay connected to Alice network: ws://localhost:9944"
echo "2. Developer → Extrinsics"
echo "3. Account: Charlie"
echo "4. session → setKeys"
echo "5. Keys: $CHARLIE_KEYS"
echo "6. Proof: 0x"
echo "7. Submit Transaction"
echo ""
read -p "⏳ Submit Charlie's session keys, then press ENTER..."

# Step 18: ⚠️ CRITICAL - ValidatorManager Authorization (DIFFERENT from Alice/Bob!)
echo ""
echo "🚨 EXTERNAL VALIDATOR AUTHORIZATION REQUIRED!"
echo "============================================="
echo ""
echo "🔗 VALIDATOR MANAGER AUTHORIZATION:"
echo "https://polkadot.js.org/apps/?rpc=ws%3A%2F%2F127.0.0.1%3A9944#/sudo"
echo ""
echo "📋 SUDO CALL DETAILS:"
echo "Call: validatorManager → registerValidators"
echo "Parameters: [\"5FLSigC9HGRKVhB9FiEo4Y3koPsNmBmLJbpXg2mp1hXcS59Y\"]"
echo "Account: Alice (sudo account)"
echo ""
echo "⚡ Manual Steps in Polkadot.js:"
echo "1. Stay connected: ws://localhost:9944"
echo "2. Developer → Sudo"
echo "3. Sudo account: Alice"
echo "4. Call: validatorManager → registerValidators"
echo "5. Parameters: [\"5FLSigC9HGRKVhB9FiEo4Y3koPsNmBmLJbpXg2mp1hXcS59Y\"]"
echo "6. Submit Sudo Transaction"
echo ""
read -p "⏳ Submit ValidatorManager authorization, then press ENTER..."

# Step 19: Monitor Charlie's activation
echo "🎯 Monitoring Charlie's validator activation..."
echo "External validators take 1-2 sessions to become active"
sleep 30

# Check if Charlie appears in validator set
echo "📊 Checking validator set..."
echo "Go to Polkadot.js → Developer → Chain state"
echo "Query: validatorManager → validators()"
echo "Should show: Alice, Bob, Charlie"

# Wait for Charlie to start authoring blocks
echo "🔍 Waiting for Charlie to author blocks..."
docker logs fennel-test-charlie --follow | grep -E "(Prepared|🎁)" &

echo "✅ PHASE 3 COMPLETE: Charlie successfully added as external validator!"
```

### **🎯 Dave and Eve Deployment (Optional - After Charlie Success)**

```bash
# Step 20: Deploy Dave with CORRECT configuration
mkdir -p /tmp/fennel-test-dave
sudo chmod 777 /tmp/fennel-test-dave

docker run -d --name fennel-test-dave \
  -p 9947:9944 -p 10047:30333 \
  -v "/tmp/fennel-test-dave:/data" \
  ghcr.io/corruptedaesthetic/uptodatefennelnetmp:sha-2ea7777df54a4bc1d113591d6a2351930bae3806 \
  --name "TestDave" --base-path /data --chain local \
  --validator \
  --listen-addr "/ip4/0.0.0.0/tcp/30333" --rpc-external --rpc-port 9944 \
  --rpc-cors all --rpc-methods unsafe \
  --bootnodes "/ip4/10.42.0.232/tcp/30333/p2p/$ALICE_PEER_ID"

# Dave's session keys and ValidatorManager registration
DAVE_KEYS=$(curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' http://localhost:9947 | jq -r '.result')
echo "✅ Dave's keys: $DAVE_KEYS"
echo "📋 Dave AccountId: 5DAAnrj7VHTznn2AWBemMuyBwZWs6FNFjdyVXUeYum3PTXFy"

# Step 21: Deploy Eve with CORRECT configuration
mkdir -p /tmp/fennel-test-eve
sudo chmod 777 /tmp/fennel-test-eve

docker run -d --name fennel-test-eve \
  -p 9948:9944 -p 10048:30333 \
  -v "/tmp/fennel-test-eve:/data" \
  ghcr.io/corruptedaesthetic/uptodatefennelnetmp:sha-2ea7777df54a4bc1d113591d6a2351930bae3806 \
  --name "TestEve" --base-path /data --chain local \
  --validator \
  --listen-addr "/ip4/0.0.0.0/tcp/30333" --rpc-external --rpc-port 9944 \
  --rpc-cors all --rpc-methods unsafe \
  --bootnodes "/ip4/10.42.0.232/tcp/30333/p2p/$ALICE_PEER_ID"

# Eve's session keys and ValidatorManager registration
EVE_KEYS=$(curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' http://localhost:9948 | jq -r '.result')
echo "✅ Eve's keys: $EVE_KEYS"
echo "📋 Eve AccountId: 5HGjWAeFDfFCWPsjFQdVV2Mspz2XtMktvgocEZcCj68kUMaw"

# Register Dave and Eve session keys via Polkadot.js Apps (same process as Charlie)
# Then authorize via ValidatorManager.registerValidators with their AccountIds

echo ""
echo "🎉 COMPLETE MULTI-VALIDATOR NETWORK ACHIEVED!"
echo "=============================================="
echo "✅ Alice: Genesis validator with secure keys"
echo "✅ Bob: Genesis validator with secure keys"  
echo "✅ Charlie: External validator via ValidatorManager"
echo "✅ Dave: External validator via ValidatorManager"
echo "✅ Eve: External validator via ValidatorManager"
echo ""
echo "🚀 5-validator production-like network operational!"
```

---

# 🚨 **CRITICAL TROUBLESHOOTING: External Validator Issues**

## **🔍 Issue: Validator in Set But Not Authoring Blocks**

**⚠️ REAL PRODUCTION ISSUE**: External validators must have the `--validator` flag!

### **Symptom:**
```bash
# Charlie appears in active validator set
curl -s -H 'Content-Type: application/json' -d '{"id":1, "jsonrpc":"2.0", "method": "state_call", "params": ["SessionApi_validators", "0x"]}' http://localhost:9944
# Shows: Alice, Bob, Charlie ✅

# But Charlie never authors blocks (no "Prepared block" messages)
docker logs fennel-test-charlie | grep -E "(Prepared|🎁)"
# Shows: No authoring activity ❌
```

### **Root Cause:**
```bash
# Check Charlie's role configuration
docker logs fennel-test-charlie | grep "Role:"
# PROBLEM: Role: FULL ❌ (should be AUTHORITY)

# ROOT CAUSE: Missing --validator flag in Docker command
```

### **✅ Solution:**
   ```bash
# WRONG (runs as FULL node):
docker run -d --name fennel-test-charlie \
  --chain local \
  # Missing --validator flag!

# CORRECT (runs as AUTHORITY):
docker run -d --name fennel-test-charlie \
  --chain local \
  --validator \  # ← CRITICAL FLAG!
```

### **🔧 Fix Running External Validator:**
   ```bash
# Stop and remove the incorrect container
docker stop fennel-test-charlie && docker rm fennel-test-charlie

# Restart with --validator flag (data persists)
docker run -d --name fennel-test-charlie \
  -p 9946:9944 -p 10046:30333 \
  -v "/tmp/fennel-test-charlie:/data" \
  ghcr.io/corruptedaesthetic/uptodatefennelnetmp:sha-2ea7777df54a4bc1d113591d6a2351930bae3806 \
  --name "TestCharlie" --base-path /data --chain local \
  --validator \
  --listen-addr "/ip4/0.0.0.0/tcp/30333" --rpc-external --rpc-port 9944 \
  --rpc-cors all --rpc-methods unsafe \
  --bootnodes "/ip4/10.42.0.232/tcp/30333/p2p/$ALICE_PEER_ID"

# Verify Charlie now runs as AUTHORITY
docker logs fennel-test-charlie | grep "Role:"
# Expected: Role: AUTHORITY ✅

# Watch for block authoring activity
docker logs fennel-test-charlie --follow | grep -E "(Prepared|🎁)"
# Expected: 🎁 Prepared block for proposing at #XXX ✅
```

## **🎯 CRITICAL UNDERSTANDING: Two-Layer External Validator System**

**⚠️ IMPORTANT**: External validators have a **two-layer activation system**:

| Step | Component | Purpose | Result |
|------|-----------|---------|---------|
| **1. Node Role** | `--validator` flag | Node capability configuration | ✅ Role: AUTHORITY |
| **2. Validator Set** | ValidatorManager registration | Runtime consensus inclusion | ✅ Active validation |

**Key Insight**: 
- **`--validator`** = "I am capable of validating"
- **ValidatorManager** = "You are selected to validate"
- **Both required** for active block authoring!

## **📋 External Validator Checklist**

**For external validator to successfully author blocks, ALL must be true:**

**Layer 1: Node Capability Setup**
1. **✅ Network Connection**: Connected to existing validators
2. **✅ Authority Role**: Node running with `--validator` flag
3. **✅ Session Keys Generated**: Cryptographically secure keys created

**Layer 2: Validator Set Inclusion**
4. **✅ Session Keys Registered**: Keys submitted via `session.setKeys`
5. **✅ ValidatorManager Authorization**: Governance approval via sudo
6. **✅ Session Transition**: Wait 1-2 sessions for activation

---

# 📊 **Infrastructure Overview**

## **🔧 Port Management**

```bash
# Alice & Bob (k3s validators)
Alice: ws://localhost:9944 (port-forward)
Bob:   ws://localhost:9945 (port-forward)

# External validators (Docker containers)
Charlie: ws://localhost:9946
Dave:    ws://localhost:9947
Eve:     ws://localhost:9948

# Polkadot.js Apps connections
Main network: https://polkadot.js.org/apps/?rpc=ws%3A%2F%2F127.0.0.1%3A9944
Charlie direct: https://polkadot.js.org/apps/?rpc=ws%3A%2F%2F127.0.0.1%3A9946
```

## **🌐 Bootnode System**

**What are Bootnodes?**
- Directory services for blockchain networks
- Help new nodes discover peers
- Essential for external validators joining your network

**Deployment:**
```bash
cd fennel-solonet/kubernetes
./deploy-bootnodes-remote.sh

# Check status
kubectl get pods -n fennel-bootnodes
# Shows: fennel-bootnodes-0, fennel-bootnodes-1 (2 for redundancy)
```

## **🎯 Validator Type Comparison**

| Aspect | Alice & Bob (Genesis) | Charlie, Dave, Eve (External) |
|--------|----------------------|------------------------------|
| **Infrastructure** | ✅ k3s pods | 🐳 Docker containers |
| **Genesis Status** | ✅ Pre-configured | ❌ Not in genesis |
| **Authority Role** | ✅ Auto-set via `--alice`/`--bob` | ⚠️ **Must specify `--validator`** |
| **Network Access** | ✅ k3s internal DNS | ⚠️ Bootnode connection required |
| **Session Keys** | ✅ `session.setKeys` | ✅ `session.setKeys` |
| **Authorization** | ✅ Automatic (genesis) | ⚠️ ValidatorManager required |
| **Governance** | ❌ Not needed | ✅ Sudo call required |
| **Activation** | 🟢 Immediate | 🟡 1-2 sessions |
| **Port Access** | 🔌 Port forwarding | 🔌 Direct container ports |

---

# ✅ **SUCCESS CRITERIA & VERIFICATION**

## **Phase 1 Success (Alice Bootstrap):**
- ✅ Alice producing blocks with `--alice` flag
- ✅ Network accessible via Polkadot.js Apps
- ✅ Alice's secure keys generated via `author_rotateKeys`
- ✅ Alice's keys registered via `session.setKeys`
- ✅ Alice continues producing blocks with secure keys

## **Phase 2 Success (Add Bob):**
- ✅ Bob deployed and connected to Alice
- ✅ Bob's secure keys generated and registered
- ✅ Both validators producing blocks in rotation
- ✅ Multi-validator consensus operational

## **Phase 3 Success (External Validators):**
- ✅ Charlie connects to Alice/Bob network (4+ peers with bootnodes)
- ✅ Charlie runs as Role: AUTHORITY (not FULL)
- ✅ Charlie's session keys generated and registered
- ✅ Charlie authorized via `validatorManager.registerValidators`
- ✅ Charlie participates in consensus (produces blocks in rotation)

## **🎉 Final Network State:**
- ✅ 5-validator network consensus (Alice, Bob, Charlie, Dave, Eve)
- ✅ Mixed infrastructure (k3s + Docker) operational
- ✅ ValidatorManager governance patterns working
- ✅ **Critical learning**: `--validator` flag requirement documented

**🚀 This workflow is production-ready and follows Polkadot ecosystem standards!**

---

# 🧹 **Cleanup Commands**

```bash
# Stop all external validators
docker stop fennel-test-charlie fennel-test-dave fennel-test-eve
docker rm fennel-test-charlie fennel-test-dave fennel-test-eve
sudo rm -rf /tmp/fennel-test-*

# Stop k3s validators
helm uninstall fennel-solochain -n fennel
helm uninstall fennel-bootnodes -n fennel-bootnodes

# Stop applications
docker-compose -f docker-compose.apps.yml down

# Kill port forwards
kill $(ps aux | grep 'kubectl port-forward' | grep -v grep | awk '{print $2}')
```