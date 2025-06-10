#!/bin/bash
set -euo pipefail

# Deterministic build script for Fennel blockchain
# Uses the same srtool approach as CI/CD pipeline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$PROJECT_ROOT/fennel-solonet"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Parse command line arguments
PUSH_IMAGES=false
BUILD_ALL=false
SKIP_RUNTIME=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH_IMAGES=true
            shift
            ;;
        --all)
            BUILD_ALL=true
            shift
            ;;
        --skip-runtime)
            SKIP_RUNTIME=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Build Fennel blockchain components deterministically

OPTIONS:
    --push           Push built images to registry
    --all            Build all services (not just fennel-solonet)
    --skip-runtime   Skip the srtool runtime build
    --help           Show this help message

EXAMPLES:
    $0                      # Build runtime and fennel-solonet image
    $0 --all                # Build all services
    $0 --push --all         # Build and push all services
    $0 --skip-runtime       # Skip runtime build (faster for testing)

ENVIRONMENT VARIABLES:
    REGISTRY                Container registry (default: ghcr.io)
    IMAGE_PREFIX            Image prefix (default: corruptedaesthetic/fennel-deploy)
    SRTOOL_VERSION          srtool version (default: 1.84.1)

EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Configuration
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_PREFIX="${IMAGE_PREFIX:-corruptedaesthetic/fennel-deploy}"
SRTOOL_VERSION="${SRTOOL_VERSION:-1.84.1}"

log "🚀 Starting deterministic build process"
log "Registry: $REGISTRY"
log "Image prefix: $IMAGE_PREFIX"
log "srtool version: $SRTOOL_VERSION"

# Ensure we're in the right directory
if [ ! -d "$RUNTIME_DIR" ]; then
    error "fennel-solonet directory not found at $RUNTIME_DIR"
    exit 1
fi

# Create artifacts directory
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts"
mkdir -p "$ARTIFACTS_DIR"

# =============================================================================
# 1. DETERMINISTIC RUNTIME BUILD
# =============================================================================
if [ "$SKIP_RUNTIME" = false ]; then
    log "🛠️  Building deterministic runtime with srtool..."
    
    cd "$RUNTIME_DIR"
    
    # Ensure Docker is available
    if ! command -v docker &> /dev/null; then
        error "Docker is required for srtool builds"
        exit 1
    fi
    
    # Build runtime with srtool
    log "Running srtool container..."
    docker run --rm \
        -v "${PWD}":/build \
        -e RUNTIME_DIR=runtime/fennel \
        -e PACKAGE=fennel-node-runtime \
        --workdir /build \
        "paritytech/srtool:$SRTOOL_VERSION" /srtool/build
    
    # Extract deterministic hash
    WASM_FILE="runtime/fennel/target/srtool/release/wbuild/fennel-node-runtime/fennel_node_runtime.compact.wasm"
    if [ -f "$WASM_FILE" ]; then
        WASM_HASH=$(sha256sum "$WASM_FILE" | awk '{print "0x"$1}')
        success "Deterministic Wasm hash: $WASM_HASH"
        
        # Store hash
        echo "$WASM_HASH" > "$ARTIFACTS_DIR/wasm-hash.txt"
        
        # Store in environment for Docker build
        export WASM_HASH
    else
        error "srtool build failed - Wasm file not found"
        exit 1
    fi
    
    cd "$PROJECT_ROOT"
else
    warning "Skipping runtime build"
    WASM_HASH="${WASM_HASH:-0x0000000000000000000000000000000000000000000000000000000000000000}"
    export WASM_HASH
fi

# =============================================================================
# 2. CONTAINER IMAGE BUILDS
# =============================================================================

build_image() {
    local service=$1
    local context=$2
    local dockerfile=${3:-Dockerfile}
    
    log "🐳 Building $service image..."
    
    local image_name="$REGISTRY/$IMAGE_PREFIX/$service"
    local tag="local-$(date +%Y%m%d-%H%M%S)"
    local full_tag="$image_name:$tag"
    
    # Build image
    docker build \
        --build-arg WASM_HASH="$WASM_HASH" \
        --tag "$full_tag" \
        --tag "$image_name:latest" \
        --file "$context/$dockerfile" \
        "$context"
    
    success "Built $service: $full_tag"
    
    # Store image info
    echo "$full_tag" > "$ARTIFACTS_DIR/$service-image.txt"
    
    # Push if requested
    if [ "$PUSH_IMAGES" = true ]; then
        log "📤 Pushing $service image..."
        docker push "$full_tag"
        docker push "$image_name:latest"
        success "Pushed $service image"
    fi
    
    return 0
}

# Build fennel-solonet
build_image "fennel-solonet" "$RUNTIME_DIR"

if [ "$BUILD_ALL" = true ]; then
    # Build additional services
    log "🔄 Building all services..."
    
    # Build fennel-service-api if it exists
    if [ -d "$PROJECT_ROOT/services/fennel-service-api/fennel-service-api" ]; then
        build_image "fennel-service-api" "$PROJECT_ROOT/services/fennel-service-api/fennel-service-api"
    fi
    
    # Build nginx proxy if it exists
    if [ -d "$PROJECT_ROOT/services/nginx/nginx" ]; then
        build_image "nginx-proxy" "$PROJECT_ROOT/services/nginx/nginx"
    fi
fi

# =============================================================================
# 3. GENERATE BUILD MANIFEST
# =============================================================================
log "📋 Generating build manifest..."

cat > "$ARTIFACTS_DIR/build-manifest.yaml" << EOF
build:
  timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
  commit: $(git rev-parse HEAD 2>/dev/null || echo "unknown")
  branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  wasm_hash: $WASM_HASH
  srtool_version: $SRTOOL_VERSION
images:
EOF

# Add image information
for image_file in "$ARTIFACTS_DIR"/*-image.txt; do
    if [ -f "$image_file" ]; then
        service=$(basename "$image_file" -image.txt)
        image=$(cat "$image_file")
        cat >> "$ARTIFACTS_DIR/build-manifest.yaml" << EOF
  $service:
    image: $image
    digest: "$(docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null || echo 'local-build')"
EOF
    fi
done

success "Build manifest generated: $ARTIFACTS_DIR/build-manifest.yaml"

# =============================================================================
# 4. SUMMARY
# =============================================================================
log "📊 Build Summary"
echo ""
echo "🏗️  Build artifacts:"
ls -la "$ARTIFACTS_DIR/"
echo ""
echo "📦 Images built:"
docker images --filter "reference=$REGISTRY/$IMAGE_PREFIX/*" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
echo ""

if [ "$PUSH_IMAGES" = true ]; then
    success "✅ All images built and pushed successfully!"
else
    success "✅ All images built successfully!"
    echo "💡 Use --push to push images to registry"
fi

if [ "$SKIP_RUNTIME" = false ]; then
    echo "🔗 Wasm hash: $WASM_HASH"
fi

echo ""
echo "🎯 Next steps:"
echo "  - Test locally: cd local-dev && docker-compose up"
echo "  - Deploy to K8s: helm upgrade --install fennel charts/fennel-solonet/"
echo "  - Update GitOps: Use artifacts for digest updates" 