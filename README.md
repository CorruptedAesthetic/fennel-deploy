# Fennel Deploy

**Polkadot SDK solochain deployment following GitOps best practices**

[![Deterministic Build & Test](https://github.com/CorruptedAesthetic/fennel-deploy/workflows/Deterministic%20Build%20%26%20Test/badge.svg)](https://github.com/CorruptedAesthetic/fennel-deploy/actions)
[![Kind Integration Tests](https://github.com/CorruptedAesthetic/fennel-deploy/workflows/Kind%20Integration%20Tests/badge.svg)](https://github.com/CorruptedAesthetic/fennel-deploy/actions)

## 🎯 Overview

This repository contains the **source code** and **Helm charts** for the Fennel blockchain - a Polkadot SDK solochain. Following Polkadot ecosystem standards, production deployment configurations are maintained in a separate private [`infra-gitops`](../infra-gitops) repository.

### 🏗️ Repository Architecture

```
fennel-deploy/               # Source code & charts (public)
├── services/                # Microservices (organized)
│   ├── fennel-service-api/  # Django REST API
│   ├── subservice/          # Supporting services  
│   ├── whiteflag-schoolpilot/ # Whiteflag protocol
│   ├── fennel-cli/          # CLI tools
│   └── nginx/               # Reverse proxy
├── fennel-solonet/          # Substrate solochain runtime
├── charts/                  # Helm charts (Parity-based)
├── local-dev/               # Development tools
├── scripts/                 # Build & CI scripts
└── .github/workflows/       # CI/CD automation

infra-gitops/                # Deployment configs (private)
├── overlays/dev/            # Development environment
├── overlays/staging/        # Staging environment  
└── overlays/prod/           # Production environment
```

## 🚀 Quick Start

### Prerequisites

- **Docker** (for building)
- **Helm 3.14+** (for charts)
- **kubectl** (for deployment)
- **Kind** (for local testing)

### Local Development

```bash
# Start development stack
cd local-dev
docker-compose up -d

# Check service health
./check-services.sh

# Test CI pipeline locally
../scripts/ci-local-test.sh
```

### Deterministic Builds

```bash
# Build runtime with srtool (same as CI)
./scripts/build-deterministic.sh

# Build all services
./scripts/build-deterministic.sh --all --push
```

### Local Kubernetes Testing

```bash
# Create Kind cluster
kind create cluster --name fennel-test

# Deploy with Helm
helm upgrade --install fennel-solonet ./charts/fennel-solonet/ \
  --namespace fennel-test --create-namespace \
  --set replicaCount=1 --set persistence.enabled=false
```

## 🏭 Production Deployment

Production deployments use **GitOps** with the separate [`infra-gitops`](../infra-gitops) repository:

1. **CI builds** deterministic images with srtool
2. **Container digests** are automatically extracted  
3. **GitOps manifests** are updated with new digests
4. **Flux/ArgoCD** deploys to environments

See [Production Deployment Guide](docs/DEPLOYMENT_SUMMARY.md) for details.

## 🛠️ CI/CD Pipeline

### GitHub Actions Workflows

- **[Deterministic Build & Test](.github/workflows/deterministic-build.yml)**
  - srtool runtime builds for reproducibility
  - Multi-service container builds with caching
  - Build manifest generation

- **[Kind Integration Tests](.github/workflows/kind-tests.yml)**  
  - Helm chart validation and linting
  - Local Kubernetes deployment testing
  - Docker Compose validation

- **[Container Digest Automation](.github/workflows/container-digest-automation.yml)**
  - Extract container digests for GitOps
  - Generate update manifests
  - Automate infra-gitops repository updates

### Local CI Testing

```bash
# Run full CI validation suite
./scripts/ci-local-test.sh

# Skip specific components  
./scripts/ci-local-test.sh --skip-kind --skip-docker
```

## 📋 Repository Structure

### Core Components

- **`fennel-solonet/`** - Substrate blockchain runtime and node
- **`services/`** - Supporting microservices (API, CLI, proxy)
- **`charts/`** - Production-ready Helm charts (based on Parity templates)

### Development & Operations

- **`local-dev/`** - Docker Compose and local development tools
- **`scripts/`** - Build automation and CI validation scripts  
- **`docs/`** - Documentation and operational guides
- **`.github/workflows/`** - CI/CD automation

## 🔧 Development Workflow

1. **Local Development**: `cd local-dev && docker-compose up`
2. **Test Changes**: `./scripts/ci-local-test.sh`
3. **Build Deterministically**: `./scripts/build-deterministic.sh`
4. **Deploy Locally**: `kind` + `helm install`
5. **Push & CI**: GitHub Actions handle the rest

## 📊 Monitoring & Validation

- **Prometheus metrics** for all services
- **Grafana dashboards** for network health
- **Kubernetes validation** with Parity's tools
- **Pre-commit hooks** for code quality

## 🔐 Security & Standards

- **Deterministic builds** with srtool
- **Container image signing** and verification
- **GitOps security** with separate deployment repo
- **Secret management** via Kubernetes secrets
- **Network policies** and pod security standards

## 📚 Documentation

- **[Progress Tracking](PROGRESS.md)** - GitOps migration status
- **[Testing Strategy](docs/TESTING_STRATEGY.md)** - Comprehensive testing guide
- **[Validator Management](docs/VALIDATOR_MANAGEMENT_WORKFLOW.md)** - Node operations
- **[Local Development](local-dev/README.md)** - Development setup

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch  
3. Run `./scripts/ci-local-test.sh`
4. Submit a pull request

For Polkadot SDK development, see [Substrate Documentation](https://docs.substrate.io/).

## 📄 License

Licensed under [Apache 2.0](LICENSE) - same as Polkadot SDK.
