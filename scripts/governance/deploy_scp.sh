#!/bin/bash

###############################################################################
# SCP Deployment Script
# 
# Deploys Service Control Policies to AWS Organizations
###############################################################################

set -euo pipefail

# Default values
POLICY_FILE=""
OU_ID=""
DESCRIPTION=""
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

Deploy Service Control Policies to AWS Organizations.

OPTIONS:
    --policy-file FILE      Path to SCP JSON policy file (required)
    --ou-id ID             Organizational Unit ID to attach policy to (required)
    --description TEXT     Policy description
    --dry-run              Show what would be done without making changes
    --confirm              Execute changes (required for actual deployment)
    --help                 Show this help message

EXAMPLES:
    $(basename "$0") --policy-file policies/scp-data-residency.json \\
        --ou-id ou-1234-abcd --description "Enforce data residency" --dry-run

    $(basename "$0") --policy-file policies/scp-data-residency.json \\
        --ou-id ou-1234-abcd --confirm

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

validate_policy_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        error "Policy file not found: $file"
    fi
    
    # Validate JSON syntax
    if ! jq empty "$file" 2>/dev/null; then
        error "Invalid JSON in policy file: $file"
    fi
    
    # Validate policy structure
    local version=$(jq -r '.Version' "$file")
    if [[ "$version" != "2012-10-17" ]]; then
        error "Policy must use Version 2012-10-17"
    fi
    
    local statement=$(jq -r '.Statement' "$file")
    if [[ "$statement" == "null" ]]; then
        error "Policy must contain Statement array"
    fi
}

###############################################################################
# Parse Arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --policy-file)
            POLICY_FILE="$2"
            shift 2
            ;;
        --ou-id)
            OU_ID="$2"
            shift 2
            ;;
        --description)
            DESCRIPTION="$2"
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

if [[ -z "$POLICY_FILE" ]]; then
    error "--policy-file is required"
fi

if [[ -z "$OU_ID" ]]; then
    error "--ou-id is required"
fi

if [[ "$CONFIRM" == false && "$DRY_RUN" == false ]]; then
    error "Either --dry-run or --confirm must be specified"
fi

validate_policy_file "$POLICY_FILE"

# Check if AWS Organizations is enabled
if ! aws organizations list-roots &>/dev/null; then
    error "AWS Organizations is not enabled or you lack permissions"
fi

###############################################################################
# Generate Policy Name
###############################################################################

POLICY_NAME=$(basename "$POLICY_FILE" .json)
POLICY_NAME="SCP-${POLICY_NAME}"

log "Policy name: $POLICY_NAME"
log "Target OU: $OU_ID"
log "Description: ${DESCRIPTION:-No description}"

###############################################################################
# Check if policy already exists
###############################################################################

EXISTING_POLICY=$(aws organizations list-policies \
    --filter SERVICE_CONTROL_POLICY \
    --query "Policies[?Name=='$POLICY_NAME'].Id" \
    --output text 2>/dev/null || true)

if [[ -n "$EXISTING_POLICY" ]]; then
    log "Policy already exists: $EXISTING_POLICY"
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would update existing policy: $EXISTING_POLICY"
    else
        log "Updating existing policy..."
        aws organizations update-policy \
            --policy-id "$EXISTING_POLICY" \
            --content file://"$POLICY_FILE" \
            --description "$DESCRIPTION" || error "Failed to update policy"
        log "Policy updated successfully"
    fi
else
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would create new policy: $POLICY_NAME"
    else
        log "Creating new policy..."
        POLICY_ID=$(aws organizations create-policy \
            --content file://"$POLICY_FILE" \
            --description "$DESCRIPTION" \
            --name "$POLICY_NAME" \
            --type SERVICE_CONTROL_POLICY \
            --query "Policy.PolicySummary.Id" \
            --output text) || error "Failed to create policy"
        log "Policy created: $POLICY_ID"
        EXISTING_POLICY="$POLICY_ID"
    fi
fi

###############################################################################
# Attach policy to OU
###############################################################################

if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would attach policy to OU: $OU_ID"
    log "[DRY-RUN] Policy ID: $EXISTING_POLICY"
else
    # Check if already attached
    ATTACHED_POLICIES=$(aws organizations list-policies-for-target \
        --target-id "$OU_ID" \
        --filter SERVICE_CONTROL_POLICY \
        --query "Policies[?Id=='$EXISTING_POLICY'].Id" \
        --output text 2>/dev/null || true)
    
    if [[ "$ATTACHED_POLICIES" == "$EXISTING_POLICY" ]]; then
        log "Policy already attached to OU"
    else
        log "Attaching policy to OU..."
        aws organizations attach-policy \
            --policy-id "$EXISTING_POLICY" \
            --target-id "$OU_ID" || error "Failed to attach policy"
        log "Policy attached successfully"
    fi
fi

if [[ "$DRY_RUN" == false ]]; then
    log "SCP deployment completed successfully"
    log "Policy ID: $EXISTING_POLICY"
    log "Attached to OU: $OU_ID"
fi
