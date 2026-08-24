#!/bin/bash

###############################################################################
# MTD Alarm Creation Script
# 
# Creates CloudWatch alarms for Maximum Tolerable Downtime monitoring
###############################################################################

set -euo pipefail

# Default values
ALARM_NAME=""
METRIC_NAME=""
NAMESPACE=""
THRESHOLD=""
COMPARISON="GreaterThanThreshold"
PERIOD=300
EVALUATION_PERIODS=1
CRITICALITY="High"
SNS_TOPIC=""
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

Create CloudWatch alarm for MTD monitoring.

OPTIONS:
    --alarm-name NAME       Alarm name (required)
    --metric-name NAME      Metric name (required)
    --namespace NAMESPACE   Metric namespace (required)
    --threshold VALUE       Alarm threshold (required)
    --comparison OPERATOR   Comparison operator (default: GreaterThanThreshold)
    --period SECONDS        Metric period in seconds (default: 300)
    --evaluation-periods N  Number of evaluation periods (default: 1)
    --criticality LEVEL     Criticality level for tagging (default: High)
    --sns-topic ARN         SNS topic ARN for notifications
    --dry-run              Show what would be done without making changes
    --confirm              Execute changes (required for actual creation)
    --help                 Show this help message

EXAMPLES:
    $(basename "$0") --alarm-name DR-MTD-PrimaryHealth \\
        --metric-name PrimaryRegionHealthCheckFailureDuration \\
        --namespace DR --threshold 3600 --dry-run

    $(basename "$0") --alarm-name DR-MTD-PrimaryHealth \\
        --metric-name PrimaryRegionHealthCheckFailureDuration \\
        --namespace DR --threshold 3600 --confirm

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

validate_comparison() {
    local op="$1"
    case "$op" in
        GreaterThanThreshold|LessThanThreshold|GreaterThanOrEqualToThreshold|LessThanOrEqualToThreshold)
            return 0
            ;;
        *)
            error "Invalid comparison operator: $op"
            ;;
    esac
}

###############################################################################
# Parse Arguments
###############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --alarm-name)
            ALARM_NAME="$2"
            shift 2
            ;;
        --metric-name)
            METRIC_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        --comparison)
            COMPARISON="$2"
            shift 2
            ;;
        --period)
            PERIOD="$2"
            shift 2
            ;;
        --evaluation-periods)
            EVALUATION_PERIODS="$2"
            shift 2
            ;;
        --criticality)
            CRITICALITY="$2"
            shift 2
            ;;
        --sns-topic)
            SNS_TOPIC="$2"
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

if [[ -z "$ALARM_NAME" ]]; then
    error "--alarm-name is required"
fi

if [[ -z "$METRIC_NAME" ]]; then
    error "--metric-name is required"
fi

if [[ -z "$NAMESPACE" ]]; then
    error "--namespace is required"
fi

if [[ -z "$THRESHOLD" ]]; then
    error "--threshold is required"
fi

if [[ "$CONFIRM" == false && "$DRY_RUN" == false ]]; then
    error "Either --dry-run or --confirm must be specified"
fi

validate_comparison "$COMPARISON"

###############################################################################
# Build Alarm Configuration
###############################################################################

log "Creating CloudWatch alarm..."
log "Alarm name: $ALARM_NAME"
log "Metric: $NAMESPACE/$METRIC_NAME"
log "Threshold: $THRESHOLD"
log "Comparison: $COMPARISON"
log "Period: ${PERIOD}s"
log "Evaluation periods: $EVALUATION_PERIODS"
log "Criticality: $CRITICALITY"

if [[ -n "$SNS_TOPIC" ]]; then
    log "SNS topic: $SNS_TOPIC"
fi

###############################################################################
# Create Alarm
###############################################################################

if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would create CloudWatch alarm: $ALARM_NAME"
    log "[DRY-RUN] Use --confirm to create alarm"
else
    # Check if alarm already exists
    EXISTING=$(aws cloudwatch describe-alarms \
        --alarm-names "$ALARM_NAME" \
        --query "MetricAlarms[0].AlarmName" \
        --output text 2>/dev/null || true)
    
    if [[ "$EXISTING" == "$ALARM_NAME" ]]; then
        log "Alarm already exists, updating..."
        aws cloudwatch put-metric-alarm \
            --alarm-name "$ALARM_NAME" \
            --metric-name "$METRIC_NAME" \
            --namespace "$NAMESPACE" \
            --threshold "$THRESHOLD" \
            --comparison-operator "$COMPARISON" \
            --period "$PERIOD" \
            --evaluation-periods "$EVALUATION_PERIODS" \
            --statistic "Maximum" \
            --alarm-description "MTD monitoring alarm for $CRITICALITY criticality resources" \
            ${SNS_TOPIC:+--alarm-actions "$SNS_TOPIC"} \
            ${SNS_TOPIC:+--ok-actions "$SNS_TOPIC"} \
            --tags "Key=Criticality,Value=$CRITICALITY" "Key=Purpose,Value=DR-Monitoring" || error "Failed to update alarm"
    else
        log "Creating new alarm..."
        aws cloudwatch put-metric-alarm \
            --alarm-name "$ALARM_NAME" \
            --metric-name "$METRIC_NAME" \
            --namespace "$NAMESPACE" \
            --threshold "$THRESHOLD" \
            --comparison-operator "$COMPARISON" \
            --period "$PERIOD" \
            --evaluation-periods "$EVALUATION_PERIODS" \
            --statistic "Maximum" \
            --alarm-description "MTD monitoring alarm for $CRITICALITY criticality resources" \
            ${SNS_TOPIC:+--alarm-actions "$SNS_TOPIC"} \
            ${SNS_TOPIC:+--ok-actions "$SNS_TOPIC"} \
            --tags "Key=Criticality,Value=$CRITICALITY" "Key=Purpose,Value=DR-Monitoring" || error "Failed to create alarm"
    fi
    
    log "Alarm created/updated successfully"
fi
