#!/bin/bash
# 🚀 GitOps Migration Progress Tracker
# Helps systematically track completion of the 10-step migration

set -e

PROGRESS_FILE="PROGRESS.md"
GUIDE_FILE="../NOTES/REPOORGANIZATIONJUNE2025/PROGRESSGUIDE.txt"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  status      - Show current progress"
    echo "  complete N  - Mark step N as complete and commit"
    echo "  milestone N - Create milestone tag for step N"
    echo "  next        - Show what to do next"
    echo "  rollback    - Emergency rollback to backup"
    echo "  help        - Show this help"
}

show_status() {
    echo -e "${BLUE}📊 GitOps Migration Progress${NC}"
    echo "=================================="
    
    if [[ -f "$PROGRESS_FILE" ]]; then
        # Extract the progress table
        sed -n '/Progress Overview/,/Legend/p' "$PROGRESS_FILE" | head -n -2
    else
        echo -e "${RED}❌ PROGRESS.md not found${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${YELLOW}📍 Current Status:${NC}"
    git log --oneline -3 | head -3
}

complete_step() {
    local step_num=$1
    
    if [[ -z "$step_num" ]]; then
        echo -e "${RED}❌ Please specify step number (1-10)${NC}"
        exit 1
    fi
    
    if [[ ! "$step_num" =~ ^[1-9]|10$ ]]; then
        echo -e "${RED}❌ Step must be between 1-10${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}📝 Completing Step $step_num${NC}"
    
    # Prompt for completion message
    echo "Enter brief description of what was completed:"
    read -r description
    
    if [[ -z "$description" ]]; then
        description="Step $step_num completed"
    fi
    
    # Stage all changes and commit
    git add .
    git commit -m "Step $step_num Complete: $description"
    
    local commit_hash=$(git rev-parse --short HEAD)
    echo -e "${GREEN}✅ Step $step_num committed: $commit_hash${NC}"
    
    # Update PROGRESS.md
    local current_date=$(date +%Y-%m-%d)
    
    # This is a simplified update - in practice you'd want to programmatically update the table
    echo -e "${YELLOW}📝 Please manually update PROGRESS.md with:${NC}"
    echo "   - Status: ✅ COMPLETE"
    echo "   - Completion Date: $current_date"
    echo "   - Git Commit: $commit_hash"
}

create_milestone() {
    local step_num=$1
    
    if [[ -z "$step_num" ]]; then
        echo -e "${RED}❌ Please specify step number (1-10)${NC}"
        exit 1
    fi
    
    local tag_name="milestone/step-$step_num-complete"
    
    echo -e "${BLUE}🏷️ Creating milestone tag: $tag_name${NC}"
    git tag "$tag_name"
    
    echo -e "${GREEN}✅ Milestone tag created: $tag_name${NC}"
    echo -e "${YELLOW}💡 To push tags: git push origin --tags${NC}"
}

show_next() {
    echo -e "${BLUE}⏭️ Next Steps${NC}"
    echo "=============="
    
    if [[ -f "$PROGRESS_FILE" ]]; then
        # Find the next step (marked with ⏳)
        grep -A 10 "⏳ NEXT" "$PROGRESS_FILE" || echo "No next step found in PROGRESS.md"
    fi
    
    echo ""
    echo -e "${YELLOW}📖 For detailed instructions, see:${NC}"
    echo "   $GUIDE_FILE"
}

emergency_rollback() {
    echo -e "${RED}🚨 EMERGENCY ROLLBACK${NC}"
    echo "======================"
    echo "This will reset to backup/pre-gitops-split and lose all uncommitted changes!"
    echo -e "${YELLOW}Are you sure? Type 'YES' to confirm:${NC}"
    read -r confirmation
    
    if [[ "$confirmation" == "YES" ]]; then
        git reset --hard backup/pre-gitops-split
        git clean -fd
        echo -e "${GREEN}✅ Rolled back to backup/pre-gitops-split${NC}"
    else
        echo -e "${BLUE}❌ Rollback cancelled${NC}"
    fi
}

# Main command handling
case "${1:-help}" in
    "status")
        show_status
        ;;
    "complete")
        complete_step "$2"
        ;;
    "milestone")
        create_milestone "$2"
        ;;
    "next")
        show_next
        ;;
    "rollback")
        emergency_rollback
        ;;
    "help"|*)
        usage
        ;;
esac 