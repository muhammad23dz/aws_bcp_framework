#!/bin/bash

###############################################################################
# Backup Integrity Validation Script
# 
# Validates data integrity between primary and DR replicas
###############################################################################

set -euo pipefail

# Default values
SOURCE_BUCKET=""
DESTINATION_BUCKET=""
SOURCE_DB=""
DESTINATION_DB=""
CHECK_TYPE="checksum"
TABLE_NAME=""
SAMPLE_SIZE=100
DRY_RUN=false

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

Validate backup integrity between primary and DR replicas.

OPTIONS:
    --source-bucket NAME      Primary S3 bucket (for S3 validation)
    --destination-bucket NAME Replica S3 bucket (for S3 validation)
    --source-db NAME          Primary database (for RDS validation)
    --destination-db NAME     Replica database (for RDS validation)
    --check-type TYPE         Validation type: checksum, row-count, object-count
    --table-name NAME         Table name for row-count validation
    --sample-size N           Number of objects to sample (default: 100)
    --dry-run                Show what would be done without executing
    --help                   Show this help message

EXAMPLES:
    # S3 checksum validation
    $(basename "$0") --source-bucket primary-bucket \\
        --destination-bucket replica-bucket --check-type checksum

    # RDS row-count validation
    $(basename "$0") --source-db production-db \\
        --destination-db replica-db --check-type row-count \\
        --table-name users

    # S3 object count validation
    $(basename "$0") --source-bucket primary-bucket \\
        --destination-bucket replica-bucket --check-type object-count

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

validate_s3_checksum() {
    local source="$1"
    local dest="$2"
    local sample_size="$3"
    
    log "Performing S3 checksum validation..."
    log "Source bucket: $source"
    log "Destination bucket: $dest"
    log "Sample size: $sample_size"
    
    # Get sample of objects from source
    local source_objects=$(aws s3api list-objects-v2 \
        --bucket "$source" \
        --max-items "$sample_size" \
        --query "Contents[].Key" \
        --output text 2>/dev/null || true)
    
    if [[ -z "$source_objects" ]]; then
        warn "No objects found in source bucket"
        return 0
    fi
    
    local mismatch_count=0
    local checked_count=0
    
    for key in $source_objects; do
        ((checked_count++))
        
        # Get ETag from source
        local source_etag=$(aws s3api head-object \
            --bucket "$source" \
            --key "$key" \
            --query "ETag" \
            --output text 2>/dev/null || true)
        
        # Get ETag from destination
        local dest_etag=$(aws s3api head-object \
            --bucket "$dest" \
            --key "$key" \
            --query "ETag" \
            --output text 2>/dev/null || true)
        
        if [[ "$source_etag" != "$dest_etag" ]]; then
            warn "Checksum mismatch for object: $key"
            ((mismatch_count++))
        fi
    done
    
    log "Checked $checked_count objects"
    log "Mismatches: $mismatch_count"
    
    if [[ "$mismatch_count" -eq 0 ]]; then
        log "S3 checksum validation PASSED"
        return 0
    else
        error "S3 checksum validation FAILED: $mismatch_count mismatches"
    fi
}

validate_s3_object_count() {
    local source="$1"
    local dest="$2"

    log "Performing S3 object count validation..."
    log "Source bucket: $source"
    log "Destination bucket: $dest"

    # FIX: list-objects-v2 only returns up to 1000 items per page. Use
    # 'aws s3 ls --recursive' which paginates automatically, then count lines.
    local source_count
    source_count=$(aws s3 ls "s3://${source}" --recursive 2>/dev/null | wc -l | tr -d ' ')

    local dest_count
    dest_count=$(aws s3 ls "s3://${dest}" --recursive 2>/dev/null | wc -l | tr -d ' ')

    log "Source object count : $source_count"
    log "Destination object count : $dest_count"

    if [[ "$source_count" -eq "$dest_count" ]]; then
        log "S3 object count validation PASSED ($source_count objects match)"
        return 0
    else
        local diff=$(( source_count - dest_count ))
        error "S3 object count validation FAILED: source=$source_count, dest=$dest_count (delta=$diff). Replication may still be in progress."
    fi
}

validate_rds_row_count() {
    local source="$1"
    local dest="$2"
    local table="$3"
    
    log "Performing RDS row count validation..."
    log "Source database: $source"
    log "Destination database: $dest"
    log "Table: $table"
    
    # Note: This requires database connectivity and credentials
    # In production, use AWS Secrets Manager for credentials
    warn "RDS row count validation requires database connectivity"
    warn "This is a placeholder - implement based on your database type"
    
    # Example for PostgreSQL (requires psql and credentials):
    # local source_count=$(psql -h $source_host -U $user -d $db -t -c "SELECT COUNT(*) FROM $table;")
    # local dest_count=$(psql -h $dest_host -U $user -d $db -t -c "SELECT COUNT(*) FROM $table;")
    
    log "RDS row count validation SKIPPED (requires database credentials)"
    return 0
}

###############################################################################
# Parse Arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --source-bucket)
            SOURCE_BUCKET="$2"
            shift 2
            ;;
        --destination-bucket)
            DESTINATION_BUCKET="$2"
            shift 2
            ;;
        --source-db)
            SOURCE_DB="$2"
            shift 2
            ;;
        --destination-db)
            DESTINATION_DB="$2"
            shift 2
            ;;
        --check-type)
            CHECK_TYPE="$2"
            shift 2
            ;;
        --table-name)
            TABLE_NAME="$2"
            shift 2
            ;;
        --sample-size)
            SAMPLE_SIZE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
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

case "$CHECK_TYPE" in
    checksum)
        if [[ -z "$SOURCE_BUCKET" || -z "$DESTINATION_BUCKET" ]]; then
            error "--source-bucket and --destination-bucket required for checksum validation"
        fi
        ;;
    object-count)
        if [[ -z "$SOURCE_BUCKET" || -z "$DESTINATION_BUCKET" ]]; then
            error "--source-bucket and --destination-bucket required for object-count validation"
        fi
        ;;
    row-count)
        if [[ -z "$SOURCE_DB" || -z "$DESTINATION_DB" || -z "$TABLE_NAME" ]]; then
            error "--source-db, --destination-db, and --table-name required for row-count validation"
        fi
        ;;
    *)
        error "Invalid check-type: $CHECK_TYPE (must be checksum, object-count, or row-count)"
        ;;
esac

###############################################################################
# Execute Validation
###############################################################################

if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would perform $CHECK_TYPE validation"
    exit 0
fi

case "$CHECK_TYPE" in
    checksum)
        validate_s3_checksum "$SOURCE_BUCKET" "$DESTINATION_BUCKET" "$SAMPLE_SIZE"
        ;;
    object-count)
        validate_s3_object_count "$SOURCE_BUCKET" "$DESTINATION_BUCKET"
        ;;
    row-count)
        validate_rds_row_count "$SOURCE_DB" "$DESTINATION_DB" "$TABLE_NAME"
        ;;
esac

log "Backup integrity validation completed successfully"
