#!/bin/bash
# Fennel Deploy Service Health Check Script

echo "🔍 Checking Fennel Deploy Services..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Blockchain - needs POST request with JSON data
echo -n "✓ Blockchain (9945): "
if curl -s -f -X POST -H "Content-Type: application/json" -d '{"id":1,"jsonrpc":"2.0","method":"system_health","params":[]}' http://localhost:9945 > /dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
fi

# API - check if Django is responding (may show 404 but that's ok)
echo -n "✓ API (1234): "
if curl -s http://localhost:1234/api/v1/ | grep -q "Page not found" > /dev/null 2>&1; then
    echo "OK (Django running)"
elif curl -s -f http://localhost:1234/api/v1/ > /dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
fi

# Apps
echo -n "✓ WhiteFlag App (3000): "
curl -s -f http://localhost:3000 > /dev/null 2>&1 && echo "OK" || echo "FAILED"

echo -n "✓ Substrate UI (8000): "
curl -s -f http://localhost:8000 > /dev/null 2>&1 && echo "OK" || echo "FAILED"

# CLI - check if port is open since it might not have HTTP endpoint
echo -n "✓ Fennel CLI (9030): "
if nc -z localhost 9030 2>/dev/null; then
    echo "OK"
else
    echo "FAILED"
fi

# Subservice - use the healthcheck endpoint
echo -n "✓ Subservice (6060): "
curl -s -f http://localhost:6060/healthcheck > /dev/null 2>&1 && echo "OK" || echo "FAILED"

# Nginx Proxies
echo -n "✓ App Nginx (8080): "
curl -s -f http://localhost:8080 > /dev/null 2>&1 && echo "OK" || echo "FAILED"

# API Nginx - may redirect or show API page
echo -n "✓ API Nginx (8081): "
if curl -s -L http://localhost:8081 | grep -q "api" > /dev/null 2>&1; then
    echo "OK"
else
    echo "FAILED"
fi

echo -n "✓ Substrate Nginx (8082): "
curl -s -f http://localhost:8082 > /dev/null 2>&1 && echo "OK" || echo "FAILED"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Additional service checks
echo ""
echo "📊 Service Details:"
echo -n "   Blockchain height: "
curl -s -X POST -H "Content-Type: application/json" -d '{"id":1,"jsonrpc":"2.0","method":"chain_getHeader","params":[]}' http://localhost:9945 2>/dev/null | grep -o '"number":"[^"]*"' | cut -d'"' -f4 | xargs printf "%d\n" 2>/dev/null || echo "Unable to fetch"

# Summary
echo ""
echo "💡 Tip: For detailed logs, use: docker-compose logs [service-name]"
echo "🔗 Access Polkadot.js at: https://polkadot.js.org/apps/?rpc=ws://localhost:9945" 