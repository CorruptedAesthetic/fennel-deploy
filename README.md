# Fennel Deploy

This repository contains the deployment setup for the Fennel blockchain network and applications.

## Quick Start

### Port Configuration

**Application Services:**
- WhiteFlag App: http://localhost:3001 (changed from 3000 to avoid Grafana conflicts)
- API: http://localhost:1234
- App Nginx: http://localhost:8080
- Service Nginx: http://localhost:8081
- Subservice: http://localhost:6060
- Fennel CLI: http://localhost:9030

**Blockchain Services:**
- Alice (k3s): ws://localhost:9944 (via port-forward)
- Bob (k3s): ws://localhost:9945 (via port-forward) 
- Single chain (Docker): ws://localhost:9945
- Prometheus metrics: http://localhost:9615

**Monitoring (can now run alongside applications):**
- Grafana: http://localhost:3000 (system-wide installation)

## Three Testing Scenarios

### Scenario 1: Docker Compose with Single Chain
```bash
docker-compose up -d
# Access: WhiteFlag app at http://localhost:3001
```

### Scenario 2: Docker Compose (Apps) + k3s (Multi-Validator) - RECOMMENDED
```bash
# 1. Cleanup first
./cleanup-environment.sh quick

# 2. Deploy Alice + Bob network
./deploy-scenario2.sh alice-bob

# Access: WhiteFlag app at http://localhost:3001
# Access: Polkadot.js via ws://localhost:9944
```

### Scenario 3: k3s Only
```bash
cd fennel-solonet/kubernetes
./deploy-fennel.sh
```

## Benefits of New Port Layout

✅ **Grafana Always Available**: Industry standard port 3000 preserved
✅ **No Port Conflicts**: WhiteFlag app on 3001 eliminates conflicts  
✅ **Monitoring + Apps**: Both can run simultaneously
✅ **Production Ready**: Follows DevOps best practices

## Quick Start: Automated Deployment

For a quick automated deployment of the Fennel network, use our deployment script:

```bash
# Initialize and update submodules
$ git submodule init
$ git submodule update

# Deploy Alice + Bob validators (recommended)
$ ./deploy-scenario2.sh alice-bob

# Optional: Add external validators (Charlie, Dave, Eve)
$ ./deploy-scenario2.sh phase3
```

### Available Deployment Commands

```bash
# Core Blockchain Deployment
$ ./deploy-scenario2.sh alice-bob    # Deploy Alice + Bob automated workflow (default)
$ ./deploy-scenario2.sh phase0       # Deploy dedicated bootnode infrastructure
$ ./deploy-scenario2.sh phase1       # Deploy Alice bootstrap
$ ./deploy-scenario2.sh phase2       # Scale to Alice + Bob
$ ./deploy-scenario2.sh phase3       # Deploy external validators (Charlie, Dave, Eve)
$ ./deploy-scenario2.sh full         # Complete 5-validator workflow

# Dashboard & Integration
$ ./deploy-scenario2.sh validate-dashboard  # Test dashboard functionality
$ ./deploy-scenario2.sh setup-dashboard     # Fix Docker + k3s integration

# Monitoring & Troubleshooting
$ ./deploy-scenario2.sh monitor      # Show monitoring commands and status
$ ./deploy-scenario2.sh diagnose     # Diagnose port forwarding issues
```

### Environment Cleanup

```bash
# Quick cleanup (preserves important data)
$ ./cleanup-environment.sh quick

# Complete reset (DESTRUCTIVE)
$ ./cleanup-environment.sh complete
```

## Running the Distribution Manually

If you prefer to run services manually instead of using the automated deployment, you can use:

```bash
$ docker compose up
```

to run local copies of all required services.

## Accessing the App

You'll find Fennel Labs' build of the app at http://localhost:3000.

## Communicating with the API

Point any apps you need to interact with the Fennel API at http://localhost:1234/api/v1/. The API might take several minutes to run all tests and confirm full availability.

## Configuring Your Account
You'll need someone set up as an administrator of an API group in order to manage accounts and their related blockchain assets. Navigate to http://localhost:1234/api/dashboard/ to get started. You'll need to create an account, then follow the instructions on-screen to get set up with a group and a blockchain address.

![Group Creation](img/group.png)

From there, click Create a Wallet to get an address on our blockchain. This will give you a sequence of letters and numbers that you'll need to use to send yourself tokens.

![Create a Wallet](img/admin.png)

![Address Display](img/address.png)
