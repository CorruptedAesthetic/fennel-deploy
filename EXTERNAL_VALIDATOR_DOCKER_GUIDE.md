# External Validator Docker Deployment Guide

## Overview

This guide explains how to deploy Charlie, Dave, and Eve as **external validators using Docker containers** rather than k3s pods. This mixed deployment architecture simulates a real-world production scenario where some validators run in your managed cluster (Alice & Bob) while others run externally.

## 🏗️ Mixed Deployment Architecture

### Internal Validators (k3s Pods)
- ✅ **Alice** (`fennel-solochain-node-0`) - Primary validator in k3s
- ✅ **Bob** (`fennel-solochain-node-1`) - Secondary validator in k3s
- ✅ **Bootnodes** - Discovery service for external validators

### External Validators (Docker Containers)
- 🐳 **Charlie** - Docker container on port 9946
- 🐳 **Dave** - Docker container on port 9947
- 🐳 **Eve** - Docker container on port 9948

## ⚖️ Development vs Production Configurations

### 🚨 Development Configuration (--dev flag)
**Use for**: Quick testing, development, learning
**Security Level**: Low (not suitable for production)

```bash
# Development flags (enabled by --dev)
--chain=dev                    # Development chain spec
--force-authoring             # Bypasses normal consensus
--rpc-cors=all                # Security risk - allows any origin
--alice                       # Uses Alice's development keys
```

**Pros:**
- ✅ Quick setup
- ✅ Works immediately
- ✅ Good for testing

**Cons:**
- ❌ Major security risks
- ❌ Uses development keys
- ❌ Bypasses consensus rules
- ❌ Unrestricted CORS access

### ✅ Production Configuration (Specific Flags)
**Use for**: Real validators, production deployment, security testing
**Security Level**: High (production-ready)

```bash
# Production flags (manual configuration)
--chain fennel                # Production chain spec
--validator                   # Enable validator mode
--rpc-external               # Enable external RPC access
--rpc-methods Safe           # Restrict to safe RPC methods
--rpc-cors "specific-origins" # Restrict CORS to authorized origins
--bootnodes "peer-addresses" # Connect to production bootnodes
```

**Pros:**
- ✅ Production security
- ✅ Uses validator's own keys
- ✅ Follows normal consensus
- ✅ Restricted network access

**Cons:**
- ⚠️ More complex setup
- ⚠️ Requires bootnode configuration
- ⚠️ Need to manage own keys

## 🚀 Deployment Methods

### Method 1: Development Testing (Quick Start)
```bash
# For development/testing only
./test-charlie-dave-eve-final.sh --test-all
```

### Method 2: Production Configuration (Recommended for Real Validators)
```bash
# For production-ready testing
./test-charlie-dave-eve-production.sh --test
```

### Method 3: Manual Production Deployment
```bash
# Stop any existing containers
docker stop fennel-test-charlie 2>/dev/null || true
docker rm fennel-test-charlie 2>/dev/null || true

# Create data directory
mkdir -p /tmp/fennel-test-charlie
chmod 777 /tmp/fennel-test-charlie

# Production configuration
docker run -d \
  --name fennel-test-charlie \
  -p 9946:9944 \
  -p 10046:30333 \
  -v /tmp/fennel-test-charlie:/data \
  --user "$(id -u):$(id -g)" \
  ghcr.io/corruptedaesthetic/uptodatefennelnetmp:sha-204fa8e5891442d07ab060fb2ff7301703b5a4df \
  --name "TestCharlie" \
  --base-path /data \
  --chain local \
  --rpc-external \
  --rpc-methods Safe \
  --rpc-cors "http://localhost:*,http://127.0.0.1:*,https://localhost:*,https://127.0.0.1:*,https://polkadot.js.org" \
  --rpc-max-connections 100 \
  --listen-addr "/ip4/0.0.0.0/tcp/30333" \
  --log info
```

## 🔗 Connection Options

### Polkadot.js Apps Connection

#### Development Configuration
```
ws://localhost:9946  # Charlie
ws://localhost:9947  # Dave  
ws://localhost:9948  # Eve
```

#### Production Configuration
Same URLs, but with restricted CORS for security.

### RPC Health Check
```bash
curl -H "Content-Type: application/json" \
  -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' \
  http://localhost:9946
```

## 🔑 Session Key Generation

### Generate Keys
```bash
curl -H "Content-Type: application/json" \
  -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' \
  http://localhost:9946
```

### Set Keys On-Chain
1. Connect to Alice's node: `ws://localhost:9944`
2. Go to Developer > Extrinsics
3. Select Charlie's account as sender
4. Call: `session.setKeys(session_keys, 0x00)`
5. Submit transaction

## 🛠️ Real External Validator Setup

For actual external validators (not testing), follow these steps:

### 1. Build fennel-node Binary
```bash
git clone https://github.com/fennelLabs/fennel-node
cd fennel-node
cargo build --release
# Binary at ./target/release/fennel-node
```

### 2. Production Configuration
```bash
./target/release/fennel-node \
  --name "YourValidatorName" \
  --base-path /your/data/path \
  --chain fennel \
  --validator \
  --rpc-external \
  --rpc-methods Safe \
  --rpc-cors "http://localhost:*,https://polkadot.js.org" \
  --rpc-max-connections 100 \
  --listen-addr "/ip4/0.0.0.0/tcp/30333" \
  --bootnodes "/ip4/BOOTNODE_IP/tcp/30333/p2p/PEER_ID" \
  --log info
```

### 3. Security Considerations
- Use firewall to restrict RPC access
- Consider VPN for RPC connections  
- Monitor for unauthorized access
- Use TLS proxy for WebSocket connections
- Rotate session keys regularly

## 🔧 Troubleshooting

### Common Issues

#### 1. Permission Denied Error
```
Error: Failed to create RocksDB directory: Permission denied
```
**Solution**: Ensure data directory has proper permissions:
```bash
chmod 777 /tmp/fennel-test-charlie
```

#### 2. CORS Error in Browser
```
Access blocked by CORS policy
```
**Development**: Use `--dev` flag or add `--rpc-cors all`
**Production**: Add specific origins to `--rpc-cors`

#### 3. Container Exits Immediately
**Check logs**: `docker logs fennel-test-charlie`
**Common cause**: Unsupported arguments or missing chain spec

#### 4. RPC Not Responding
**Wait**: Node may still be starting up
**Check**: `docker ps` to see if container is running
**Test**: Use curl command to test RPC endpoint

### Log Analysis
```bash
# Monitor real-time logs
docker logs -f fennel-test-charlie

# Check last 20 log lines
docker logs fennel-test-charlie | tail -20

# Look for specific errors
docker logs fennel-test-charlie 2>&1 | grep -i error
```

## 🎯 When to Use Each Method

### Use Development Configuration When:
- ✅ Learning the validator setup process
- ✅ Quick testing and iteration
- ✅ Demonstrating functionality
- ✅ Development environment

### Use Production Configuration When:
- ✅ Setting up real validators
- ✅ Security testing
- ✅ Pre-production validation
- ✅ Training for production deployment

## 📋 Summary

The external validator Docker deployment supports both **development** (using `--dev`) and **production** (using specific flags) configurations. Choose the appropriate method based on your use case:

- **Development**: Fast and easy, but insecure
- **Production**: Secure and proper, but requires more setup

This mixed k3s + Docker architecture effectively simulates real-world validator deployment scenarios where some validators run in managed infrastructure while others operate independently. 