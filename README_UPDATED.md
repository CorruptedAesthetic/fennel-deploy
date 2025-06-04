# Fennel Deploy Updates: External Validator Docker Deployment

## Summary of Changes

This update clarifies the proper deployment method for Charlie, Dave, and Eve as external validators using Docker containers rather than k3s pods.

## Key Changes Made

### 1. New External Validator Docker Guide
- **Created**: `EXTERNAL_VALIDATOR_DOCKER_GUIDE.md`
- **Purpose**: Complete guide for deploying Charlie, Dave, and Eve as Docker containers
- **Includes**: Mixed deployment architecture explanation, step-by-step deployment, troubleshooting

### 2. Updated TESTING_GUIDE.md
- **Added**: External Validator Docker Deployment section at the end
- **Clarified**: Charlie, Dave, and Eve are Docker containers, not k3s pods
- **Referenced**: New external validator Docker guide

## Mixed Deployment Architecture (By Design)

### Internal Validators (k3s Pods)
- ✅ **Alice** (`fennel-solochain-node-0`) - Primary validator in k3s
- ✅ **Bob** (`fennel-solochain-node-1`) - Secondary validator in k3s
- ✅ **Bootnodes** - Discovery service for external validators

### External Validators (Docker Containers)
- 🐳 **Charlie** - Docker container on port 9946
- 🐳 **Dave** - Docker container on port 9947  
- 🐳 **Eve** - Docker container on port 9948

## Why This Architecture?

This mixed deployment approach provides several benefits:

1. **Real-world simulation**: Tests external validator onboarding process
2. **Network discovery**: Validates bootnode functionality  
3. **Production readiness**: Ensures your network can handle external participants
4. **Operator training**: Provides hands-on experience with validator management
5. **Emergency testing**: Allows testing of validator removal/addition procedures

## How to Deploy External Validators

### Quick Method
```bash
cd fennel-solonet/kubernetes
./test-charlie-dave-eve.sh --test-all
```

### Interactive Method
```bash
cd fennel-solonet/kubernetes
./test-charlie-dave-eve.sh
# Select option 1 for full workflow
# Or option 2 for individual deployment
```

## Verification

After deployment, verify each validator is running:

```bash
# Check Charlie (port 9946)
curl -H "Content-Type: application/json" \
  -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' \
  http://localhost:9946

# Check Docker containers
docker ps | grep fennel-test
```

Expected output:
```bash
fennel-test-charlie   # Running on port 9946
fennel-test-dave      # Running on port 9947  
fennel-test-eve       # Running on port 9948
```

## Connection to Individual Validators

### Option 1: Direct Connection to Charlie
1. **First, ensure Charlie is deployed** (see above)
2. Open Polkadot.js Apps in a new browser tab/window
3. Click the network dropdown (top-left corner)
4. Select "Development" → "Custom"
5. Enter Charlie's endpoint: `ws://localhost:9946`
6. Click "Switch"

### Option 2: Use Main Network for Transactions
1. Keep your existing connection to `ws://localhost:9944` (Alice/Bob)
2. Use Charlie/Dave/Eve for session key generation only
3. Submit all transactions via the main network connection

## References

- **[EXTERNAL_VALIDATOR_DOCKER_GUIDE.md](EXTERNAL_VALIDATOR_DOCKER_GUIDE.md)** - Complete Docker deployment guide
- **[TESTING_GUIDE.md](TESTING_GUIDE.md)** - Main testing guide with updated external validator section
- **[test-charlie-dave-eve.sh](fennel-solonet/kubernetes/test-charlie-dave-eve.sh)** - Deployment script 