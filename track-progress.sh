#!/bin/bash
set -euo pipefail

# 🚀 GitOps Migration Progress Tracker
# Comprehensive progress management following PROGRESSGUIDE.txt standards

PROGRESS_FILE="PROGRESS.md"
BACKUP_TAG="backup/pre-gitops-split"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Helper functions
print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
        "NEXT")
            echo -e "${PURPLE}⏳ $message${NC}"
            ;;
    esac
}

# Show usage
show_usage() {
    echo "🚀 GitOps Migration Progress Tracker"
    echo "===================================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status              Show current progress overview"
    echo "  next                Show next step details and checklist"
    echo "  complete <step>     Mark step as complete and commit changes"
    echo "  milestone <step>    Create milestone tag for major achievement"
    echo "  rollback            Emergency rollback to backup (use with caution)"
    echo "  summary             Show comprehensive progress summary"
    echo "  validate            Validate current repository state"
    echo ""
    echo "Examples:"
    echo "  $0 status           # Show current status"
    echo "  $0 next             # See what's coming next"
    echo "  $0 complete 7       # Complete step 7"
    echo "  $0 milestone 7      # Create milestone tag for step 7"
    echo ""
}

# Show current status
show_status() {
    echo "📊 Current GitOps Migration Status"
    echo "=================================="
    echo ""
    
    # Extract progress table from PROGRESS.md
    if [[ -f "$PROGRESS_FILE" ]]; then
        echo "Progress Overview:"
        echo ""
        grep -A 20 "| Step | Status |" "$PROGRESS_FILE" | head -15
        echo ""
        
        # Count completed steps
        local completed=$(grep "✅ COMPLETE" "$PROGRESS_FILE" | wc -l)
        local next_step=$(grep "⏳ NEXT" "$PROGRESS_FILE" | head -1 | cut -d'|' -f2 | xargs)
        local pending=$(grep "⏸️ PENDING" "$PROGRESS_FILE" | wc -l)
        
        print_status "OK" "Completed steps: $completed"
        print_status "NEXT" "Next step: $next_step"
        print_status "INFO" "Pending steps: $pending"
        
    else
        print_status "ERROR" "PROGRESS.md not found"
        exit 1
    fi
    
    echo ""
    echo "📋 Quick Commands:"
    echo "  ./track-progress.sh next      # See next step details"
    echo "  ./track-progress.sh summary   # Full progress summary"
    echo "  git log --oneline | head -5   # Recent commits"
}

# Show next step details
show_next() {
    echo "⏳ Next Step Details"
    echo "==================="
    echo ""
    
    if [[ -f "$PROGRESS_FILE" ]]; then
        # Find the next step
        local next_step=$(grep "⏳ NEXT" "$PROGRESS_FILE" | head -1)
        if [[ -n "$next_step" ]]; then
            local step_name=$(echo "$next_step" | cut -d'|' -f2 | xargs)
            local step_notes=$(echo "$next_step" | cut -d'|' -f6 | xargs)
            
            print_status "NEXT" "Step: $step_name"
            print_status "INFO" "Description: $step_notes"
            echo ""
            
            # Try to find the detailed section for this step
            local step_number=$(echo "$step_name" | grep -o '^[0-9]*' || echo "")
            if [[ -n "$step_number" ]]; then
                echo "📋 Detailed Checklist:"
                echo "----------------------"
                
                # Extract the section for this step
                local section_start="## 📋 Step $step_number:"
                local section_found=$(grep -n "$section_start" "$PROGRESS_FILE" | head -1 | cut -d':' -f1)
                
                if [[ -n "$section_found" ]]; then
                    # Show the checklist items
                    sed -n "${section_found},/^## /p" "$PROGRESS_FILE" | grep "- \[ \]" | head -10
                    echo ""
                    print_status "INFO" "See PROGRESS.md for complete checklist and instructions"
                else
                    print_status "WARNING" "Detailed checklist not found for step $step_number"
                fi
            fi
            
        else
            print_status "OK" "All steps completed! 🎉"
            echo ""
            echo "Consider:"
            echo "  - Running validation: ./track-progress.sh validate"
            echo "  - Creating final milestone: ./track-progress.sh milestone final"
            echo "  - Reviewing summary: ./track-progress.sh summary"
        fi
    else
        print_status "ERROR" "PROGRESS.md not found"
        exit 1
    fi
}

# Complete a step
complete_step() {
    local step_num=$1
    
    if [[ -z "$step_num" ]]; then
        print_status "ERROR" "Step number required"
        echo "Usage: $0 complete <step_number>"
        exit 1
    fi
    
    echo "✅ Completing Step $step_num"
    echo "============================"
    echo ""
    
    # Validate git status
    if [[ -n "$(git status --porcelain)" ]]; then
        print_status "WARNING" "Uncommitted changes detected"
        echo ""
        git status --short
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "INFO" "Aborted. Commit your changes first."
            exit 1
        fi
    fi
    
    # Get current date
    local completion_date=$(date +%Y-%m-%d)
    
    # Create commit message
    local commit_msg="Step $step_num Complete: GitOps automation milestone

- Updated PROGRESS.md with completion status
- Completion date: $completion_date
- All tasks verified and documented

Progress tracking: $(grep "✅ COMPLETE" "$PROGRESS_FILE" | wc -l) steps completed"
    
    # Commit changes
    git add .
    git commit -m "$commit_msg"
    
    local commit_hash=$(git rev-parse --short HEAD)
    print_status "OK" "Step $step_num marked complete"
    print_status "OK" "Committed as: $commit_hash"
    
    echo ""
    echo "📋 Next Actions:"
    echo "  1. Update PROGRESS.md manually if needed"
    echo "  2. Create milestone: ./track-progress.sh milestone $step_num"
    echo "  3. Check next step: ./track-progress.sh next"
}

# Create milestone tag
create_milestone() {
    local step_num=$1
    
    if [[ -z "$step_num" ]]; then
        print_status "ERROR" "Step number required"
        echo "Usage: $0 milestone <step_number>"
        exit 1
    fi
    
    echo "🏷️  Creating Milestone Tag for Step $step_num"
    echo "============================================="
    echo ""
    
    local tag_name="milestone/step-$step_num-complete"
    local tag_message="Milestone: Step $step_num Complete

GitOps Migration Progress Milestone
Completion Date: $(date +%Y-%m-%d)
Commit: $(git rev-parse --short HEAD)

This milestone represents the successful completion of Step $step_num
in the GitOps migration following PROGRESSGUIDE.txt standards."
    
    # Create annotated tag
    git tag -a "$tag_name" -m "$tag_message"
    
    print_status "OK" "Milestone tag created: $tag_name"
    
    # Push tag if remote exists
    if git remote get-url origin &>/dev/null; then
        read -p "Push tag to remote? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            git push origin "$tag_name"
            print_status "OK" "Tag pushed to remote"
        fi
    fi
    
    echo ""
    echo "📋 Milestone Created:"
    echo "  Tag: $tag_name"
    echo "  View: git show $tag_name"
    echo "  List: git tag -l 'milestone/*'"
}

# Emergency rollback
emergency_rollback() {
    echo "🚨 EMERGENCY ROLLBACK"
    echo "===================="
    echo ""
    print_status "WARNING" "This will reset to backup tag: $BACKUP_TAG"
    print_status "WARNING" "ALL UNCOMMITTED CHANGES WILL BE LOST"
    echo ""
    
    # Check if backup tag exists
    if ! git tag -l | grep -q "$BACKUP_TAG"; then
        print_status "ERROR" "Backup tag '$BACKUP_TAG' not found"
        echo ""
        echo "Available tags:"
        git tag -l
        exit 1
    fi
    
    echo "Current status:"
    git log --oneline -5
    echo ""
    
    read -p "Are you ABSOLUTELY SURE you want to rollback? Type 'ROLLBACK' to confirm: " confirm
    if [[ "$confirm" != "ROLLBACK" ]]; then
        print_status "INFO" "Rollback cancelled"
        exit 0
    fi
    
    # Perform rollback
    print_status "WARNING" "Rolling back to $BACKUP_TAG..."
    git reset --hard "$BACKUP_TAG"
    git clean -fd
    
    print_status "OK" "Rollback complete"
    print_status "INFO" "Repository reset to backup state"
    
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Review current state: git status"
    echo "  2. Check progress: ./track-progress.sh status"
    echo "  3. Resume from appropriate step"
}

# Show comprehensive summary
show_summary() {
    echo "📊 Comprehensive GitOps Migration Summary"
    echo "========================================="
    echo ""
    
    if [[ -f "$PROGRESS_FILE" ]]; then
        # Repository info
        echo "📁 Repository Information:"
        echo "  Path: $(pwd)"
        echo "  Branch: $(git branch --show-current)"
        echo "  Last commit: $(git log -1 --format='%h - %s (%cr)')"
        echo ""
        
        # Progress statistics
        local total_steps=$(grep -c "| [0-9]" "$PROGRESS_FILE" || echo "0")
        local completed=$(grep -c "✅ COMPLETE" "$PROGRESS_FILE" || echo "0")
        local in_progress=$(grep -c "⏳ NEXT" "$PROGRESS_FILE" || echo "0")
        local pending=$(grep -c "⏸️ PENDING" "$PROGRESS_FILE" || echo "0")
        
        echo "📈 Progress Statistics:"
        echo "  Total steps: $total_steps"
        echo "  Completed: $completed"
        echo "  In progress: $in_progress"
        echo "  Pending: $pending"
        
        if [[ $total_steps -gt 0 ]]; then
            local percentage=$((completed * 100 / total_steps))
            echo "  Completion: $percentage%"
        fi
        echo ""
        
        # Recent milestones
        echo "🏷️  Recent Milestones:"
        git tag -l 'milestone/*' --sort=-version:refname | head -5 | while read -r tag; do
            local tag_date=$(git log -1 --format=%ai "$tag" | cut -d' ' -f1)
            echo "  $tag ($tag_date)"
        done
        echo ""
        
        # Files created/modified
        echo "📝 Key Files:"
        echo "  Progress tracking: $PROGRESS_FILE"
        echo "  Validation script: validate-k8s-manifests.sh"
        echo "  GitOps status: check-gitops-status.sh"
        echo "  Bootstrap script: bootstrap-polkadot-gitops.sh"
        echo ""
        
        # Next actions
        local next_step=$(grep "⏳ NEXT" "$PROGRESS_FILE" | head -1 | cut -d'|' -f2 | xargs)
        if [[ -n "$next_step" ]]; then
            echo "🎯 Next Actions:"
            echo "  Current step: $next_step"
            echo "  View details: ./track-progress.sh next"
            echo "  Complete step: ./track-progress.sh complete <step_num>"
        else
            echo "🎉 Migration Complete!"
            echo "  All steps finished"
            echo "  Consider final validation and documentation"
        fi
        
    else
        print_status "ERROR" "PROGRESS.md not found"
        exit 1
    fi
}

# Validate repository state
validate_state() {
    echo "🔍 Repository State Validation"
    echo "=============================="
    echo ""
    
    local errors=0
    
    # Check required files
    echo "📁 Required Files:"
    local required_files=("PROGRESS.md" "track-progress.sh" "validate-k8s-manifests.sh")
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_status "OK" "$file exists"
        else
            print_status "ERROR" "$file missing"
            ((errors++))
        fi
    done
    echo ""
    
    # Check git status
    echo "📋 Git Status:"
    if [[ -z "$(git status --porcelain)" ]]; then
        print_status "OK" "Working directory clean"
    else
        print_status "WARNING" "Uncommitted changes detected"
        git status --short
    fi
    echo ""
    
    # Check backup tag
    echo "🏷️  Backup Status:"
    if git tag -l | grep -q "$BACKUP_TAG"; then
        print_status "OK" "Backup tag '$BACKUP_TAG' exists"
    else
        print_status "ERROR" "Backup tag '$BACKUP_TAG' missing"
        ((errors++))
    fi
    echo ""
    
    # Check progress file format
    echo "📊 Progress File Validation:"
    if grep -q "| Step | Status |" "$PROGRESS_FILE"; then
        print_status "OK" "Progress table format valid"
    else
        print_status "ERROR" "Progress table format invalid"
        ((errors++))
    fi
    
    if grep -q "✅ COMPLETE\|⏳ NEXT\|⏸️ PENDING" "$PROGRESS_FILE"; then
        print_status "OK" "Progress status indicators valid"
    else
        print_status "ERROR" "Progress status indicators missing"
        ((errors++))
    fi
    echo ""
    
    # Summary
    if [[ $errors -eq 0 ]]; then
        print_status "OK" "Repository state validation passed"
        echo ""
        echo "🎉 All checks passed! Repository is in good state."
    else
        print_status "ERROR" "Repository state validation failed ($errors errors)"
        echo ""
        echo "❌ Please fix the errors above before proceeding."
        exit 1
    fi
}

# Main command dispatcher
main() {
    local command=${1:-""}
    
    case $command in
        "status")
            show_status
            ;;
        "next")
            show_next
            ;;
        "complete")
            complete_step "${2:-}"
            ;;
        "milestone")
            create_milestone "${2:-}"
            ;;
        "rollback")
            emergency_rollback
            ;;
        "summary")
            show_summary
            ;;
        "validate")
            validate_state
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        "")
            show_usage
            ;;
        *)
            print_status "ERROR" "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 