#!/bin/bash

###############################################################################
# Drill Instance Launch Script
# 
# Launches sandboxed drill instances for DR testing
###############################################################################

set -euo pipefail

# Default values
AMI_ID=""
INSTANCE_TYPE="t3.micro"
DR_REGION=""
SUBNET_ID=""
SECURITY_GROUP_ID=""
PURPOSE="DR-Drill"
CRITICALITY="High"
TEARDOWN=false
DRILL_ID=""
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

Launch or teardown drill instances for DR testing.

OPTIONS:
    --ami-id ID            AMI ID for drill instance (required for launch)
    --instance-type TYPE   Instance type (default: t3.micro)
    --dr-region REGION     DR region (required)
    --subnet-id ID         Subnet ID (required for launch)
    --security-group-id ID Security group ID (required for launch)
    --purpose PURPOSE      Purpose tag (default: DR-Drill)
    --criticality LEVEL    Criticality level (default: High)
    --teardown             Teardown mode instead of launch
    --drill-id ID          Drill instance ID (required for teardown)
    --dry-run              Show what would be done without making changes
    --confirm              Execute changes (required for actual launch/teardown)
    --help                 Show this help message

EXAMPLES:
    $(basename "$0") --ami-id ami-12345678 --instance-type t3.micro \\
        --dr-region us-west-2 --subnet-id subnet-12345 \\
        --security-group-id sg-12345 --dry-run

    $(basename "$0") --ami-id ami-12345678 --instance-type t3.micro \\
        --dr-region us-west-2 --subnet-id subnet-12345 \\
        --security-group-id sg-12345 --confirm

    $(basename "$0") --teardown --drill-id i-drill-12345 \\
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

validate_network_isolation() {
    local sg_id="$1"
    local region="$2"
    
    log "Validating network isolation for security group: $sg_id"
    
    # Check for rules allowing production CIDR
    local prod_rules=$(aws ec2 describe-security-groups \
        --group-ids "$sg_id" \
        --region "$region" \
        --query "SecurityGroups[0].IpPermissions[?contains(IpRanges[].CidrIp, '10.0.0.0/16')]" \
        --output text 2>/dev/null || true)
    
    if [[ -n "$prod_rules" ]]; then
        warn "Security group allows production CIDR - review network isolation"
    else
        log "Network isolation validated"
    fi
}

###############################################################################
# Parse Arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --ami-id)
            AMI_ID="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --dr-region)
            DR_REGION="$2"
            shift 2
            ;;
        --subnet-id)
            SUBNET_ID="$2"
            shift 2
            ;;
        --security-group-id)
            SECURITY_GROUP_ID="$2"
            shift 2
            ;;
        --purpose)
            PURPOSE="$2"
            shift 2
            ;;
        --criticality)
            CRITICALITY="$2"
            shift 2
            ;;
        --teardown)
            TEARDOWN=true
            shift
            ;;
        --drill-id)
            DRILL_ID="$2"
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

if [[ -z "$DR_REGION" ]]; then
    error "--dr-region is required"
fi

if [[ "$CONFIRM" == false && "$DRY_RUN" == false ]]; then
    error "Either --dry-run or --confirm must be specified"
fi

if [[ "$TEARDOWN" == true ]]; then
    if [[ -z "$DRILL_ID" ]]; then
        error "--drill-id is required for teardown"
    fi
else
    if [[ -z "$AMI_ID" ]]; then
        error "--ami-id is required for launch"
    fi
    if [[ -z "$SUBNET_ID" ]]; then
        error "--subnet-id is required for launch"
    fi
    if [[ -z "$SECURITY_GROUP_ID" ]]; then
        error "--security-group-id is required for launch"
    fi
fi

###############################################################################
# Teardown Mode
###############################################################################

if [[ "$TEARDOWN" == true ]]; then
    log "Starting drill instance teardown..."
    log "Drill instance: $DRILL_ID"
    log "Region: $DR_REGION"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would terminate drill instance: $DRILL_ID"
    else
        # Verify instance has drill tag
        # Verify instance has drill tag before terminating — safety guardrail
        INSTANCE_PURPOSE=$(aws ec2 describe-tags \
            --filters "Name=resource-id,Values=$DRILL_ID" "Name=key,Values=Purpose" \
            --region "$DR_REGION" \
            --query "Tags[?Key=='Purpose'].Value" \
            --output text 2>/dev/null || true)

        if [[ ! "$INSTANCE_PURPOSE" =~ DR-Drill ]]; then
            error "Instance $DRILL_ID does not have Purpose=DR-Drill tag — refusing teardown as a safety check"
        fi

        log "Terminating drill instance $DRILL_ID..."
        aws ec2 terminate-instances \
            --instance-ids "$DRILL_ID" \
            --region "$DR_REGION" || error "Failed to terminate instance"

        log "Waiting for instance to reach terminated state..."
        aws ec2 wait instance-terminated \
            --instance-ids "$DRILL_ID" \
            --region "$DR_REGION" || warn "Timeout waiting for instance termination"

        log "Drill instance $DRILL_ID terminated successfully"
    fi
    exit 0
fi

###############################################################################
# Launch Mode
###############################################################################

log "Starting drill instance launch..."
log "AMI: $AMI_ID"
log "Instance type: $INSTANCE_TYPE"
log "Subnet: $SUBNET_ID"
log "Security group: $SECURITY_GROUP_ID"
log "Region: $DR_REGION"
log "Purpose: $PURPOSE"
log "Criticality: $CRITICALITY"

validate_network_isolation "$SECURITY_GROUP_ID" "$DR_REGION"

DRILL_TIMESTAMP=$(date +%s)
DRILL_TAG="DrillID=${DRILL_TIMESTAMP}"

if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would launch drill instance"
    log "[DRY-RUN] Tags: Purpose=$PURPOSE, Criticality=$CRITICALITY, $DRILL_TAG, AutoTeardown=4h"
    log "[DRY-RUN] Use --confirm to launch instance"
else
    log "Launching drill instance..."
    
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --subnet-id "$SUBNET_ID" \
        --security-group-ids "$SECURITY_GROUP_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Purpose,Value=$PURPOSE},{Key=Criticality,Value=$CRITICALITY},{Key=$DRILL_TAG},{Key=AutoTeardown,Value=4h},{Key=Environment,Value=Drill}]" \
        --region "$DR_REGION" \
        --query "Instances[0].InstanceId" \
        --output text) || error "Failed to launch instance"
    
    log "Drill instance launched successfully"
    log "Instance ID: $INSTANCE_ID"
    log "Drill ID: $DRILL_TIMESTAMP"
    
    log "Waiting for instance to be running..."
    aws ec2 wait instance-running \
        --instance-ids "$INSTANCE_ID" \
        --region "$DR_REGION" || warn "Timeout waiting for instance"
    
    log "Drill instance is running"
    log "Teardown command: $(basename "$0") --teardown --drill-id $INSTANCE_ID --dr-region $DR_REGION --confirm"
fi
