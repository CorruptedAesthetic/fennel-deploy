#!/bin/bash

# 🧹 Comprehensive Fennel Blockchain Cleanup Script
# This script ensures ALL blockchain data is removed for a clean deployment

set -e

echo "🧹 COMPREHENSIVE FENNEL BLOCKCHAIN CLEANUP"
echo "=========================================="
echo "This script will remove ALL blockchain data, Docker volumes, and containers."
echo "WARNING: This is irreversible!"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "🔄 Step 1: Cleaning external validators and bootnodes..."
./deploy-external-validators-with-bootnodes.sh clean 2>/dev/null || echo "External validator script not found or no external validators to clean"
./deploy-bootnodes.sh clean 2>/dev/null || echo "Bootnode script not found or no bootnodes to clean"

echo "🔄 Step 2: Stopping Docker Compose services..."
docker-compose -f docker-compose.apps.yml down 2>/dev/null || true
docker-compose down 2>/dev/null || true

echo "🔄 Step 3: Stopping and removing ALL Docker containers..."
docker stop $(docker ps -aq) 2>/dev/null || echo "No containers to stop"
docker rm $(docker ps -aq) 2>/dev/null || echo "No containers to remove"

echo "🔄 Step 4: Removing ALL Docker images (including cached)..."
docker rmi $(docker images -aq) -f 2>/dev/null || echo "No images to remove"

echo "🔄 Step 5: 🚨 CRITICAL - Removing ALL Docker volumes (including blockchain data)..."
# List volumes first so user can see what's being removed
echo "Current volumes:"
docker volume ls
echo ""
# Remove ALL volumes (this includes blockchain data volumes)
docker volume rm $(docker volume ls -q) 2>/dev/null || echo "No volumes to remove"

echo "🔄 Step 6: Aggressive Docker system cleanup..."
docker system prune -a -f --volumes

echo "🔄 Step 7: Cleaning k3s cluster..."
sudo k3s-uninstall.sh 2>/dev/null || echo "k3s not installed or already cleaned"

echo "🔄 Step 8: Stopping Grafana..."
sudo systemctl stop grafana-server 2>/dev/null || sudo service grafana-server stop 2>/dev/null || sudo kill 1500 2>/dev/null || echo "Grafana not running"

echo "🔄 Step 9: Cleaning temporary directories..."
sudo rm -rf /tmp/fennel-* 2>/dev/null || echo "No /tmp/fennel-* directories found"
rm -rf ./chain-data/* 2>/dev/null || echo "No local chain-data directory found"
rm -rf ./validator-data/* 2>/dev/null || echo "No validator-data directory found"
rm -rf ./bootnode-data/* 2>/dev/null || echo "No bootnode-data directory found"
rm -rf ./bootnode-keys/* 2>/dev/null || echo "No bootnode-keys directory found"

echo "🔄 Step 10: Cleaning ports..."
sudo lsof -ti:9944,9933,30333,9615,8080,8081,8082,3000,1234,6060,9030,8000,9945,9946,9947,9948 2>/dev/null | xargs -r sudo kill -9 || echo "No processes found on fennel ports"

echo "🔄 Step 11: Removing Docker networks..."
docker network ls | grep -v "bridge\|host\|none" | awk 'NR>1 {print $1}' | xargs -r docker network rm 2>/dev/null || echo "No custom networks to remove"

echo ""
echo "✅ VERIFICATION - Final system state:"
echo "======================================"
echo "Docker system usage:"
docker system df
echo ""
echo "Remaining volumes:"
docker volume ls
echo ""
echo "Running containers:"
docker ps
echo ""
echo "Port usage on fennel ports:"
netstat -tulpn 2>/dev/null | grep -E ":(9944|9933|30333|9615)" || echo "No fennel ports in use"

echo ""
echo "🎉 COMPREHENSIVE CLEANUP COMPLETE!"
echo "=================================="
echo "✅ All Docker containers, images, and volumes removed"
echo "✅ All blockchain data permanently deleted"
echo "✅ All fennel-related processes terminated"
echo "✅ All ports freed"
echo "✅ k3s cluster uninstalled"
echo "✅ Temporary directories cleaned"
echo ""
echo "🚀 System is now COMPLETELY CLEAN for fresh deployment!"
echo "💡 You can now safely follow the testing guide instructions." 