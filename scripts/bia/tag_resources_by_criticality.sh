#!/bin/bash

###############################################################################
# BIA Resource Tagging Script
# 
# Tags AWS resources with criticality levels for Business Impact Analysis
# Supports tagging and querying resources by criticality
###############################################################################

set -euo pipefail

# Default values
CRITICALITY=""
RTO=""
RPO=""
DR_REGION=""
RESOURCE_IDS=""
QUERY_ONLY=false
DRY_RUN=false
CONFIRM=false
ENVIRONMENT=""
FORMAT="table"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

###############################################################################
# Functions
###############################################################################

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Tag AWS resources with criticality levels for Business Impact Analysis.

OPTIONS:
    --criticality LEVEL      Criticality level: High, Medium, or Low (required for tagging)
    --rto HOURS              Recovery Time Objective in hours
    --rpo MINUTES            Recovery Point Objective in minutes
    --dr-region REGION       Target DR region (e.g., us-west-2)
    --resource-ids IDS       Comma-separated list of resource IDs/ARNs to tag
    --query                  Query mode: list resources by criticality
    --environment ENV        Filter by environment (for query mode)
    --format FORMAT          Output format: table, json, text (default: table)
    --dry-run                Show what would be done without making changes
    --confirm                Execute changes (required for actual tagging)
    --help                   Show this help message

EXAMPLES:
    # Tag resources as high criticality
    $(basename "$0") --criticality High --rto 1 --rpo 5 --dr-region us-west-2 \\
        --resource-ids i-1234567890abcdef0,db-production-1 --dry-run

    # Query high-criticality resources
    $(basename "$0") --query --criticality High --environment Production

    # Apply tags after dry-run review
    $(basename "$0") --criticality High --rto 1 --rpo 5 --dr-region us-west-2 \\
        --resource-ids i-1234567890abcdef0 --confirm

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

validate_criticality() {
    local level="$1"
    if [[ ! "$level" =~ ^(High|Medium|Low)$ ]]; then
        error "Criticality must be High, Medium, or Low"
    fi
}

validate_environment() {
    if [[ -n "$ENVIRONMENT" && ! "$ENVIRONMENT" =~ ^(Production|Staging|Development)$ ]]; then
        warn "Environment should be Production, Staging, or Development"
    fi
}

tag_resource() {
    local resource_id="$1"
    local tags="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would tag resource: $resource_id"
        log "[DRY-RUN] Tags: $tags"
        return 0
    fi
    
    # Determine resource type and tag accordingly
    if [[ "$resource_id" =~ ^i- ]]; then
        # EC2 instance
        aws ec2 create-tags \
            --resources "$resource_id" \
            --tags "$tags" || error "Failed to tag EC2 instance $resource_id"
    elif [[ "$resource_id" =~ ^vol- ]]; then
        # EC2 volume
        aws ec2 create-tags \
            --resources "$resource_id" \
            --tags "$tags" || error "Failed to tag volume $resource_id"
    elif [[ "$resource_id" =~ ^sg- ]]; then
        # Security group
        aws ec2 create-tags \
            --resources "$resource_id" \
            --tags "$tags" || error "Failed to tag security group $resource_id"
    elif [[ "$resource_id" =~ ^arn:aws:rds: ]]; then
        # RDS instance
        local db_id=$(echo "$resource_id" | awk -F: '{print $NF}')
        aws rds add-tags-to-resource \
            --resource-name "$resource_id" \
            --tags "$tags" || error "Failed to tag RDS instance $resource_id"
    elif [[ "$resource_id" =~ ^arn:aws:s3::: ]]; then
        # S3 bucket
        local bucket_name=$(echo "$resource_id" | sed 's/arn:aws:s3::://')
        aws s3api put-bucket-tagging \
            --bucket "$bucket_name" \
            --tagging "TagSet=$tags" || error "Failed to tag S3 bucket $resource_id"
    else
        # Generic resource tagging
        aws resourcegroupstaggingapi tag-resources \
            --resource-tag-list "$tags" \
            --resource-arn-list "$resource_id" || error "Failed to tag resource $resource_id"
    fi
    
    log "Successfully tagged resource: $resource_id"
}

query_resources() {
    local criticality="$1"
    local environment="$2"
    
    local query='{"ResourceTypeFilters":["AWS::AllSupported"],"TagFilters":[]}'
    
    if [[ -n "$criticality" ]]; then
        query=$(echo "$query" | jq --arg key "Criticality" --arg value "$criticality" \
            '.TagFilters += [{"Key": $key, "Values": [$value]}]')
    fi
    
    if [[ -n "$environment" ]]; then
        query=$(echo "$query" | jq --arg key "Environment" --arg value "$environment" \
            '.TagFilters += [{"Key": $key, "Values": [$value]}]')
    fi
    
    log "Querying resources with criticality: ${criticality:-All}, environment: ${environment:-All}"
    
    local result=$(aws resourcegroupsstaggingapi get-resources \
        --resource-tag-filters "Key=Criticality,Values=${criticality:-*}" \
        --resources-per-page 100 2>/dev/null || error "Failed to query resources")
    
    if [[ "$FORMAT" == "json" ]]; then
        echo "$result" | jq '.ResourceTagMappingList'
    elif [[ "$FORMAT" == "text" ]]; then
        echo "$result" | jq -r '.ResourceTagMappingList[].ResourceARN'
    else
        echo "$result" | jq -r '.ResourceTagMappingList[] | "\(.ResourceARN)\t\(.Tags | map(.Key + "=" + .Value) | join(", "))"' \
            | column -t -s $'\t'
    fi
}

###############################################################################
# Parse Arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --criticality)
            CRITICALITY="$2"
            shift 2
            ;;
        --rto)
            RTO="$2"
            shift 2
            ;;
        --rpo)
            RPO="$2"
            shift 2
            ;;
        --dr-region)
            DR_REGION="$2"
            shift 2
            ;;
        --resource-ids)
            RESOURCE_IDS="$2"
            shift 2
            ;;
        --query)
            QUERY_ONLY=true
            shift
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
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

if [[ "$QUERY_ONLY" == true ]]; then
    validate_criticality "$CRITICALITY" || true
    validate_environment
    query_resources "$CRITICALITY" "$ENVIRONMENT"
    exit 0
fi

if [[ -z "$CRITICALITY" ]]; then
    error "--criticality is required for tagging mode"
fi

validate_criticality "$CRITICALITY"

if [[ -z "$RESOURCE_IDS" ]]; then
    error "--resource-ids is required for tagging mode"
fi

if [[ "$CONFIRM" == false && "$DRY_RUN" == false ]]; then
    error "Either --dry-run or --confirm must be specified"
fi

###############################################################################
# Build Tags
###############################################################################

TAGS="Key=Criticality,Value=$CRITICALITY"

if [[ -n "$RTO" ]]; then
    TAGS="$TAGS Key=RTO,Value=$RTO"
fi

if [[ -n "$RPO" ]]; then
    TAGS="$TAGS Key=RPO,Value=$RPO"
fi

if [[ -n "$DR_REGION" ]]; then
    TAGS="$TAGS Key=DR-Region,Value=$DR_REGION"
fi

if [[ -n "$ENVIRONMENT" ]]; then
    TAGS="$TAGS Key=Environment,Value=$ENVIRONMENT"
fi

TAGS="$TAGS Key=Purpose,Value=BCP-Demo"

###############################################################################
# Execute Tagging
###############################################################################

log "Tagging resources with criticality: $CRITICALITY"
log "Resource IDs: $RESOURCE_IDS"
log "Tags: $TAGS"

if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN MODE - No changes will be made"
    log "Use --confirm to apply changes"
fi

# Convert comma-separated IDs to array
IFS=',' read -ra RESOURCE_ARRAY <<< "$RESOURCE_IDS"

for resource_id in "${RESOURCE_ARRAY[@]}"; do
    # Trim whitespace
    resource_id=$(echo "$resource_id" | xargs)
    tag_resource "$resource_id" "$TAGS"
done

if [[ "$DRY_RUN" == false ]]; then
    log "Tagging completed successfully"
    log "Run with --query --criticality $CRITICALITY to verify"
fi
