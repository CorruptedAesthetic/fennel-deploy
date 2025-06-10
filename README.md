# Fennel Deploy

Production-ready deployment infrastructure for the Fennel blockchain network and applications.

## 🚀 Quick Start

### Prerequisites
- Docker
- k3s (for multi-validator scenarios)
- kubectl
- helm

### Initialize Repository
```bash
# Clone and setup
git clone https://github.com/fennellabs/fennel-deploy.git
cd fennel-deploy
git submodule init
git submodule update
```

## 🎯 Deployment Scenarios

### 1️⃣ Quick Development Setup (Single Validator)
```bash
# Start all services with a single validator
docker-compose up -d

# Access points:
# - WhiteFlag App: http://localhost:3001
# - API: http://localhost:1234
# - Blockchain RPC: ws://localhost:9945
```

### 2️⃣ Production Setup (Multi-Validator) - Recommended
```bash
# Deploy Alice + Bob validators with production configuration
./deploy-scenario2.sh alice-bob

# Access points:
# - WhiteFlag App: http://localhost:3001
# - API: http://localhost:1234
# - Blockchain RPC: ws://localhost:9944
```

### 3️⃣ Blockchain-Only Setup
```bash
cd fennel-solonet/kubernetes
./deploy-fennel.sh

# Access point:
# - Blockchain RPC: ws://localhost:9944
```

## 📋 Common Commands

```bash
# Cleanup environment (before switching scenarios)
./deploy-scenario2.sh cleanup

# Scale validators (in multi-validator setup)
./deploy-scenario2.sh phase3  # Adds Charlie, Dave, Eve

# Monitor deployment
./deploy-scenario2.sh monitor

# Troubleshooting
./deploy-scenario2.sh diagnose
```

## 🔧 Port Configuration

| Service | Port | Access URL |
|---------|------|------------|
| WhiteFlag App | 3001 | http://localhost:3001 |
| API | 1234 | http://localhost:1234 |
| Blockchain Node (Single) | 9945 | ws://localhost:9945 |
| Blockchain Node (Multi) | 9944 | ws://localhost:9944 |
| Monitoring | 3000 | http://localhost:3000 |

## 📚 Documentation

- For detailed deployment instructions and troubleshooting, see [TESTING_GUIDE.md](TESTING_GUIDE.md)
- For API documentation, visit http://localhost:1234/api/docs
- For blockchain interaction, use [Polkadot.js Apps](https://polkadot.js.org/apps)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
