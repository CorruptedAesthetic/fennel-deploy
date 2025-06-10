# Local Development Tools

This directory contains tools and configurations for local development and testing of the Fennel blockchain.

## Files

### Docker Compose
- **`docker-compose.yml`** - Main development stack with all services
- **`docker-compose.apps.yml`** - Additional application services

### Development Scripts
- **`setup-k3s.sh`** - Sets up local k3s Kubernetes cluster for testing
- **`check-services.sh`** - Health check script for all services
- **`test-bootnode-connectivity.sh`** - Tests bootnode network connectivity

### Documentation
- **`local-development-guide.md`** - Comprehensive guide for local development

## Quick Start

### Docker Compose Development
```bash
# Start all services
docker-compose up -d

# Start with additional apps
docker-compose -f docker-compose.yml -f docker-compose.apps.yml up -d

# Check service health
./check-services.sh
```

### Local Kubernetes Testing
```bash
# Set up k3s cluster
./setup-k3s.sh

# Test bootnode connectivity
./test-bootnode-connectivity.sh
```

## CI/CD Integration

### Deterministic Builds
```bash
# Build with srtool (same as CI pipeline)
../scripts/build-deterministic.sh

# Build all services
../scripts/build-deterministic.sh --all

# Test CI pipeline locally
../scripts/ci-local-test.sh
```

### Kind Integration Testing
```bash
# Test Helm charts on local Kind cluster
kind create cluster --name fennel-test
helm upgrade --install fennel-solonet ../charts/fennel-solonet/ \
  --namespace fennel-test --create-namespace \
  --set replicaCount=1 --set persistence.enabled=false
```

## Production Deployment

For production deployment, see the GitOps manifests in the separate `infra-gitops` repository.
This directory is purely for local development and testing.

### CI/CD Pipeline
The repository includes GitHub Actions workflows for:
- **Deterministic builds** with srtool
- **Kind integration tests** 
- **Container digest automation** for GitOps
- **Helm chart validation** 