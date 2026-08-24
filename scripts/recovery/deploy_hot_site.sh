#!/bin/bash

###############################################################################
# Hot Site Deployment Script
# 
# Deploys hot site infrastructure for disaster recovery
###############################################################################

set -euo pipefail

# Default values
ASG_NAME=""
CAPACITY=0
DR_REGION=""
PURPOSE="DR-Drill"
DRY_RUN=false
CONFIRM=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

###############################################################################
# Functions
###############################################################################

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Deploy or scale hot site infrastructure.

OPTIONS:
    --asg-name NAME        Auto Scaling Group name (required)
    --capacity NUMBER      Desired capacity (default: 0)
    --dr-region REGION     DR region (required)
    --purpose PURPOSE      Purpose tag: DR-Drill or Production (default: DR-Drill)
    --dry-run              Show what would be done without making changes
    --confirm              Execute changes (required for actual deployment)
    --help                 Show this help message

EXAMPLES:
    $(basename "$0") --asg-name dr-warm-standby-asg --capacity 2 \\
        --dr-region us-west-2 --dry-run

    $(basename "$0") --asg-name dr-warm-standby-asg --capacity 2 \\
        --dr-region us-west-2 --confirm

EOF
    exit 1
}

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

check_asg_exists() {
    local asg_name="$1"
    local region="$2"
    
    if ! aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --region "$region" &>/dev/null; then
        error "Auto Scaling Group not found: $asg_name in region $region"
    fi
}

get_asg_capacity() {
    local asg_name="$1"
    local region="$2"
    
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --region "$region" \
        --query "AutoScalingGroups[0].DesiredCapacity" \
        --output text
}

###############################################################################
# Parse Arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --asg-name)
            ASG_NAME="$2"
            shift 2
            ;;
        --capacity)
            CAPACITY="$2"
            shift 2
            ;;
        --dr-region)
            DR_REGION="$2"
            shift 2
            ;;
        --purpose)
            PURPOSE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --confirm)
            CONFIRM=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

###############################################################################
# Validation
###############################################################################

if [[ -z "$ASG_NAME" ]]; then
    error "--asg-name is required"
fi

if [[ -z "$DR_REGION" ]]; then
    error "--dr-region is required"
fi

if [[ "$CONFIRM" == false && "$DRY_RUN" == false ]]; then
    error "Either --dry-run or --confirm must be specified"
fi

if [[ ! "$PURPOSE" =~ ^(DR-Drill|Production)$ ]]; then
    error "Purpose must be DR-Drill or Production"
fi

###############################################################################
# Pre-flight Checks
###############################################################################

log "Starting hot site deployment..."
log "ASG name: $ASG_NAME"
log "Target capacity: $CAPACITY"
log "DR region: $DR_REGION"
log "Purpose: $PURPOSE"

check_asg_exists "$ASG_NAME" "$DR_REGION"

CURRENT_CAPACITY=$(get_asg_capacity "$ASG_NAME" "$DR_REGION")
log "Current capacity: $CURRENT_CAPACITY"

if [[ "$CURRENT_CAPACITY" == "$CAPACITY" ]]; then
    log "ASG already at desired capacity"
    exit 0
fi

###############################################################################
# Scale ASG
###############################################################################

if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would scale ASG from $CURRENT_CAPACITY to $CAPACITY"
    log "[DRY-RUN] ASG: $ASG_NAME"
    log "[DRY-RUN] Region: $DR_REGION"
    log "[DRY-RUN] Use --confirm to execute scaling"
else
    log "Scaling ASG from $CURRENT_CAPACITY to $CAPACITY..."
    
    aws autoscaling set-desired-capacity \
        --auto-scaling-group-name "$ASG_NAME" \
        --desired-capacity "$CAPACITY" \
        --region "$DR_REGION" || error "Failed to scale ASG"
    
    log "ASG scaling initiated successfully"
    
    # Wait for instances to be in service
    if [[ "$CAPACITY" -gt 0 ]]; then
        log "Waiting for instances to be in service..."
        aws autoscaling wait \
            --auto-scaling-group-name "$ASG_NAME" \
            --desired-capacity "$CAPACITY" \
            --region "$DR_REGION" || warn "Timeout waiting for instances"
        
        log "ASG scaling completed"
    else
        log "ASG scaled to 0 (instances will terminate)"
    fi
fi
