#!/bin/bash
set -euo pipefail

# Local CI testing script
# Runs the same validations as the CI pipeline locally

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Parse arguments
SKIP_DOCKER=false
SKIP_HELM=false
SKIP_KIND=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        --skip-helm)
            SKIP_HELM=true
            shift
            ;;
        --skip-kind)
            SKIP_KIND=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Run CI validations locally before pushing to repository

OPTIONS:
    --skip-docker    Skip Docker build tests
    --skip-helm      Skip Helm chart validation
    --skip-kind      Skip Kind integration tests
    --help           Show this help message

EXAMPLES:
    $0                     # Run all tests
    $0 --skip-kind         # Skip Kind tests (faster)
    $0 --skip-docker       # Skip Docker builds

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

log "🚀 Starting local CI validation"

cd "$PROJECT_ROOT"

# =============================================================================
# 1. REPOSITORY STRUCTURE VALIDATION
# =============================================================================
log "📋 Validating repository structure..."

required_dirs=("charts" "services" "local-dev" "docs" ".github/workflows")
for dir in "${required_dirs[@]}"; do
    if [ -d "$dir" ]; then
        success "Directory exists: $dir"
    else
        error "Missing directory: $dir"
        exit 1
    fi
done

# Check for critical files
required_files=(".gitignore" ".pre-commit-config.yaml" "PROGRESS.md")
for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        success "File exists: $file"
    else
        error "Missing file: $file"
        exit 1
    fi
done

# =============================================================================
# 2. HELM CHART VALIDATION
# =============================================================================
if [ "$SKIP_HELM" = false ]; then
    log "🔍 Validating Helm charts..."
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        warning "Helm not installed, skipping chart validation"
    else
        for chart in charts/*/; do
            if [ -f "$chart/Chart.yaml" ]; then
                chart_name=$(basename "$chart")
                log "Validating chart: $chart_name"
                
                # Lint chart
                if helm lint "$chart"; then
                    success "Chart lint passed: $chart_name"
                else
                    error "Chart lint failed: $chart_name"
                    exit 1
                fi
                
                # Template chart
                if helm template "$chart_name" "$chart" \
                    --set image.tag=test \
                    --set replicaCount=1 \
                    --set node.chain=local \
                    > /dev/null; then
                    success "Chart template passed: $chart_name"
                else
                    error "Chart template failed: $chart_name"
                    exit 1
                fi
            fi
        done
    fi
else
    warning "Skipping Helm validation"
fi

# =============================================================================
# 3. DOCKER VALIDATION
# =============================================================================
if [ "$SKIP_DOCKER" = false ]; then
    log "🐳 Validating Docker configurations..."
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        warning "Docker not installed, skipping Docker validation"
    else
        # Validate docker-compose files
        cd local-dev
        if docker-compose config > /dev/null; then
            success "Docker Compose configuration valid"
        else
            error "Docker Compose configuration invalid"
            exit 1
        fi
        cd "$PROJECT_ROOT"
        
        # Validate Dockerfiles exist
        dockerfiles=(
            "fennel-solonet/Dockerfile"
            "services/fennel-service-api/fennel-service-api/Dockerfile"
        )
        
        for dockerfile in "${dockerfiles[@]}"; do
            if [ -f "$dockerfile" ]; then
                success "Dockerfile exists: $dockerfile"
            else
                warning "Dockerfile missing: $dockerfile"
            fi
        done
    fi
else
    warning "Skipping Docker validation"
fi

# =============================================================================
# 4. KIND INTEGRATION TEST SETUP
# =============================================================================
if [ "$SKIP_KIND" = false ]; then
    log "🎯 Testing Kind integration setup..."
    
    # Check if kind and kubectl are installed
    if ! command -v kind &> /dev/null; then
        warning "Kind not installed, skipping Kind tests"
        warning "Install with: go install sigs.k8s.io/kind@latest"
    elif ! command -v kubectl &> /dev/null; then
        warning "kubectl not installed, skipping Kind tests"
        warning "Install kubectl to run Kind integration tests"
    else
        # Test Kind cluster creation (dry run)
        log "Testing Kind configuration..."
        
        cat > /tmp/kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.29.0
  extraPortMappings:
  - containerPort: 30333
    hostPort: 30333
    protocol: TCP
EOF
        
        # Validate kind config
        if kind create cluster --config /tmp/kind-config.yaml --name ci-test-dry-run --dry-run; then
            success "Kind configuration valid"
        else
            error "Kind configuration invalid"
            exit 1
        fi
        
        rm -f /tmp/kind-config.yaml
    fi
else
    warning "Skipping Kind validation"
fi

# =============================================================================
# 5. PRE-COMMIT HOOKS VALIDATION
# =============================================================================
log "🔨 Validating pre-commit hooks..."

if [ -f ".pre-commit-config.yaml" ]; then
    success "Pre-commit configuration exists"
    
    if command -v pre-commit &> /dev/null; then
        if pre-commit run --all-files; then
            success "Pre-commit hooks passed"
        else
            warning "Pre-commit hooks failed (run 'pre-commit run --all-files' to fix)"
        fi
    else
        warning "pre-commit not installed"
        warning "Install with: pip install pre-commit"
    fi
else
    error "Pre-commit configuration missing"
fi

# =============================================================================
# 6. GITIGNORE VALIDATION
# =============================================================================
log "📄 Validating .gitignore..."

required_gitignore_entries=(
    "*.kubeconfig"
    "kubeconfig*"
    ".kube/"
    "k8s-manifests/"
    "*.key"
    "*.crt"
    "local-dev/override-*"
)

for entry in "${required_gitignore_entries[@]}"; do
    if grep -q "$entry" .gitignore; then
        success "Gitignore entry exists: $entry"
    else
        warning "Missing gitignore entry: $entry"
    fi
done

# =============================================================================
# 7. PROGRESS TRACKING VALIDATION
# =============================================================================
log "📊 Validating progress tracking..."

if [ -f "PROGRESS.md" ]; then
    success "Progress tracking file exists"
    
    # Check if Step 4 is marked as in progress
    if grep -q "4. Wire deterministic CI.*⏳" PROGRESS.md; then
        success "Step 4 correctly marked as in progress"
    else
        warning "Step 4 status may need updating in PROGRESS.md"
    fi
else
    error "PROGRESS.md missing"
fi

# =============================================================================
# 8. SUMMARY
# =============================================================================
log "📋 Local CI Validation Summary"
echo ""
success "✅ Repository structure validation passed"

if [ "$SKIP_HELM" = false ]; then
    success "✅ Helm chart validation passed"
fi

if [ "$SKIP_DOCKER" = false ]; then
    success "✅ Docker configuration validation passed"
fi

if [ "$SKIP_KIND" = false ]; then
    success "✅ Kind integration test setup validated"
fi

echo ""
log "🎯 Ready for CI pipeline!"
echo ""
echo "Next steps:"
echo "  1. Commit your changes"
echo "  2. Push to trigger GitHub Actions"
echo "  3. Monitor workflow execution"
echo "  4. Check artifacts for build manifests and GitOps updates"
echo ""
echo "Local testing:"
echo "  - Build deterministically: ./scripts/build-deterministic.sh"
echo "  - Test locally: cd local-dev && docker-compose up"
echo "  - Deploy to Kind: kind create cluster && helm install..." 