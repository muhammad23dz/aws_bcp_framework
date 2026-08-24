#!/bin/bash

###############################################################################
# DRS Failover Script
# 
# Initiates AWS Elastic Disaster Recovery failover with safety checks
###############################################################################

set -euo pipefail

# Default values
SOURCE_SERVER_ID=""
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

Initiate AWS Elastic Disaster Recovery failover.

OPTIONS:
    --source-server-id ID   Source server ID for DRS (required)
    --dr-region REGION      Target DR region (required)
    --purpose PURPOSE       Purpose tag: DR-Drill or Production (default: DR-Drill)
    --dry-run              Show what would be done without making changes
    --confirm              Execute failover (required for actual failover)
    --help                 Show this help message

EXAMPLES:
    $(basename "$0") --source-server-id i-source-123456 \\
        --dr-region us-west-2 --dry-run

    $(basename "$0") --source-server-id i-source-123456 \\
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

check_drs_agent_status() {
    local server_id="$1"
    log "Checking DRS agent status for server: $server_id"
    
    local status=$(aws drs describe-source-servers \
        --source-server-ids "$server_id" \
        --region "$DR_REGION" \
        --query "sourceServers[0].agentStatus" \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$status" != "ACTIVE" ]]; then
        warn "DRS agent status: $status (expected: ACTIVE)"
    else
        log "DRS agent status: ACTIVE"
    fi
}

check_replication_status() {
    local server_id="$1"
    log "Checking replication status for server: $server_id"

    # BUG FIX: aws drs describe-replication-instances does NOT exist in the DRS
    # API — that belongs to AWS DMS. The correct call is describe-source-servers
    # querying the dataReplicationInfo.dataReplicationState field.
    local status
    status=$(aws drs describe-source-servers \
        --source-server-ids "$server_id" \
        --region "$DR_REGION" \
        --query "sourceServers[0].dataReplicationInfo.dataReplicationState" \
        --output text 2>/dev/null || echo "UNKNOWN")

    if [[ "$status" != "CONTINUOUS" && "$status" != "RESCAN" ]]; then
        warn "Replication status: $status (expected: CONTINUOUS or RESCAN)"
    else
        log "Replication status: $status (healthy)"
    fi
}

###############################################################################
# Parse Arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --source-server-id)
            SOURCE_SERVER_ID="$2"
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

if [[ -z "$SOURCE_SERVER_ID" ]]; then
    error "--source-server-id is required"
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

log "Starting DRS failover pre-flight checks..."
log "Source server: $SOURCE_SERVER_ID"
log "DR region: $DR_REGION"
log "Purpose: $PURPOSE"

check_drs_agent_status "$SOURCE_SERVER_ID"
check_replication_status "$SOURCE_SERVER_ID"

###############################################################################
# Initiate Failover
###############################################################################

if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would initiate DRS failover"
    log "[DRY-RUN] Source server: $SOURCE_SERVER_ID"
    log "[DRY-RUN] DR region: $DR_REGION"
    log "[DRY-RUN] Purpose: $PURPOSE"
    log "[DRY-RUN] Use --confirm to execute actual failover"
else
    log "Initiating DRS failover..."
    
    # Start recovery
    RECOVERY_ID=$(aws drs start-recovery \
        --source-server-ids "$SOURCE_SERVER_ID" \
        --region "$DR_REGION" \
        --tags "Purpose=$PURPOSE" \
        --query "job.ID" \
        --output text 2>/dev/null || error "Failed to start recovery")
    
    log "Recovery initiated successfully"
    log "Recovery job ID: $RECOVERY_ID"
    
    # Monitor recovery progress
    # BUG FIX: Initialize STATUS before the loop so that if the loop body never
    # executes (e.g., $RECOVERY_ID is empty), referencing $STATUS with set -u
    # won't cause an "unbound variable" error.
    STATUS="PENDING"
    log "Monitoring recovery progress..."
    for i in {1..30}; do
        sleep 10
        STATUS=$(aws drs describe-jobs \
            --job-ids "$RECOVERY_ID" \
            --region "$DR_REGION" \
            --query "jobs[0].status" \
            --output text 2>/dev/null || echo "UNKNOWN")

        log "Recovery status ($i/30): $STATUS"

        if [[ "$STATUS" == "COMPLETED" ]]; then
            log "Recovery completed successfully"
            break
        elif [[ "$STATUS" == "FAILED" ]]; then
            error "Recovery failed — check the DRS console for details"
        fi
    done

    if [[ "$STATUS" != "COMPLETED" ]]; then
        warn "Recovery still in progress after ~5 minutes"
        log "Check status with: aws drs describe-jobs --job-ids $RECOVERY_ID --region $DR_REGION"
    fi
fi
