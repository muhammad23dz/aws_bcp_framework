# BIA & Criticality Classification

This document maps Business Impact Analysis (BIA) outcomes to AWS resource tagging and Resource Groups, enabling automation to identify and prioritize critical assets during disaster recovery.

## Overview

Business Impact Analysis (BIA) identifies and prioritizes business functions and IT assets based on their criticality to operations. In AWS, this is operationalized through:

- **Resource Tagging** - Applying standardized tags to indicate criticality levels
- **Resource Groups** - Logical groupings based on tags for bulk operations
- **Tagging Policies** - Governance rules enforcing consistent tagging
- **Automated Tagging Scripts** - CLI tools for applying and querying tags

## BIA Criticality Levels

| Criticality Level | RTO Target | RPO Target | Recovery Strategy | Tag Value |
|---|---|---|---|---|
| **High** | < 1 hour | < 5 minutes | Hot site (DRS continuous replication) | `Criticality=High` |
| **Medium** | < 4 hours | < 1 hour | Warm standby (ASG scale-up) | `Criticality=Medium` |
| **Low** | < 24 hours | < 4 hours | Backup/restore from snapshots | `Criticality=Low` |

## Standard Tag Schema

### Required Tags for DR

| Tag Key | Description | Valid Values | Example |
|---|---|---|---|
| `Criticality` | Business criticality level | `High`, `Medium`, `Low` | `Criticality=High` |
| `RTO` | Recovery Time Objective (hours) | Numeric value | `RTO=1` |
| `RPO` | Recovery Point Objective (minutes) | Numeric value | `RPO=5` |
| `DR-Region` | Target DR region | AWS region code | `DR-Region=us-west-2` |
| `Purpose` | Resource purpose | `Production`, `DR-Drill`, `DR-WarmStandby` | `Purpose=Production` |
| `Environment` | Deployment environment | `Production`, `Staging`, `Development` | `Environment=Production` |

### Optional Tags for Enhanced Visibility

| Tag Key | Description | Example |
|---|---|---|
| `BusinessOwner` | Business unit owner | `BusinessOwner=Finance` |
| `TechnicalOwner` | Technical team owner | `TechnicalOwner=PlatformTeam` |
| `CostCenter` | Cost center code | `CostCenter=12345` |
| `Application` | Application name | `Application=PaymentProcessing` |

## BIA to AWS Resource Mapping

| BIA Component | AWS Resource Type | Tagging Strategy |
|---|---|---|
| Critical business applications | EC2 instances, ASGs, Lambda functions | `Criticality=High`, `RTO=1`, `RPO=5` |
| Databases (transactional) | RDS instances, Aurora clusters | `Criticality=High`, `RTO=1`, `RPO=5` |
| Data storage (user data) | S3 buckets, EFS volumes | `Criticality=High`, `RTO=4`, `RPO=15` |
| Authentication services | Cognito user pools, IAM resources | `Criticality=High`, `RTO=1`, `RPO=5` |
| API gateways | API Gateway REST APIs | `Criticality=Medium`, `RTO=4`, `RPO=30` |
| Analytics pipelines | EMR clusters, Redshift | `Criticality=Low`, `RTO=24`, `RPO=240` |
| Development environments | All dev resources | `Criticality=Low`, `RTO=24`, `RPO=240` |

## Resource Groups Configuration

### Resource Group: High-Criticality-Production

**Query:**
```json
{
  " ResourceTypeFilters": [
    "AWS::EC2::Instance",
    "AWS::RDS::DBInstance",
    "AWS::ElasticLoadBalancingV2::LoadBalancer",
    "AWS::Lambda::Function",
    "AWS::S3::Bucket"
  ],
  "TagFilters": [
    {
      "Key": "Criticality",
      "Values": ["High"]
    },
    {
      "Key": "Environment",
      "Values": ["Production"]
    }
  ]
}
```

**Purpose:** Group all high-criticality production resources for:
- Priority DR failover
- Enhanced monitoring
- Strict compliance controls

### Resource Group: Warm-Standby-Infrastructure

**Query:**
```json
{
  "ResourceTypeFilters": [
    "AWS::AutoScaling::AutoScalingGroup",
    "AWS::EC2::LaunchTemplate",
    "AWS::EC2::SecurityGroup"
  ],
  "TagFilters": [
    {
      "Key": "Purpose",
      "Values": ["DR-WarmStandby"]
    }
  ]
}
```

**Purpose:** Group warm standby infrastructure for:
- Drill operations
- Rapid scale-up during failover
- Cost optimization (scale to 0 when not in drill)

## Implementation

### 1. Apply Criticality Tags

```bash
# Tag high-criticality resources
./scripts/bia/tag_resources_by_criticality.sh \
  --criticality High \
  --rto 1 \
  --rpo 5 \
  --dr-region us-west-2 \
  --resource-ids i-1234567890abcdef0,db-production-1

# Tag medium-criticality resources
./scripts/bia/tag_resources_by_criticality.sh \
  --criticality Medium \
  --rto 4 \
  --rpo 60 \
  --dr-region us-west-2 \
  --resource-ids sg-abcdef123456,lt-0987654321fedcba

# Tag low-criticality resources
./scripts/bia/tag_resources_by_criticality.sh \
  --criticality Low \
  --rto 24 \
  --rpo 240 \
  --dr-region us-west-2 \
  --resource-ids bucket-analytics-data
```

### 2. Create Resource Groups

```bash
# Create high-criticality production resource group
aws resource-groups create-group \
  --name High-Criticality-Production \
  --description "High criticality production resources for DR priority" \
  --resource-query file://iac/terraform/modules/tagging-baseline/resource-group-queries/high-criticality.json

# Create warm standby resource group
aws resource-groups create-group \
  --name Warm-Standby-Infrastructure \
  --description "Warm standby infrastructure for DR drills" \
  --resource-query file://iac/terraform/modules/tagging-baseline/resource-group-queries/warm-standby.json
```

### 3. Query Resources by Criticality

```bash
# List all high-criticality resources
aws resource-groups search-resources \
  --resource-query '{
    "Type": "TAG_FILTERS_1_0",
    "Query": "{\"ResourceTypeFilters\":[\"AWS::AllSupported\"],\"TagFilters\":[{\"Key\":\"Criticality\",\"Values\":[\"High\"]}]}"
  }' \
  --output table

# Get resources needing immediate attention during incident
./scripts/bia/tag_resources_by_criticality.sh \
  --query \
  --criticality High \
  --environment Production
```

### 4. Validate Tagging Compliance

```bash
# Find untagged resources in production
aws resourcegroupsstaggingapi get-resources \
  --tag-filters Key=Environment,Values=Production \
  --resources-per-page 100 \
  --query 'ResourceTagMappingList[?Tags==null].ResourceARN' \
  --output text

# Find resources with missing criticality tags
aws resourcegroupsstaggingapi get-resources \
  --tag-filters Key=Environment,Values=Production \
  --resources-per-page 100 \
  --query 'ResourceTagMappingList[?not_contains(Tags[?Key==`Criticality`].Value, `High`) && not_contains(Tags[?Key==`Criticality`].Value, `Medium`) && not_contains(Tags[?Key==`Criticality`].Value, `Low`)].ResourceARN' \
  --output text
```

## Tagging Policy Enforcement

### AWS Tag Policy Example

```json
{
  "tags": {
    "Criticality": {
      "tag_key": {
        "@@assign": "Criticality"
      },
      "tag_values": {
        "@@assign": ["High", "Medium", "Low"]
      },
      "enforced_for": {
        "@@assign": ["ec2:instance", "rds:db", "s3:bucket"]
      }
    },
    "RTO": {
      "tag_key": {
        "@@assign": "RTO"
      },
      "tag_values": {
        "@@assign": ["1", "4", "24"]
      }
    },
    "RPO": {
      "tag_key": {
        "@@assign": "RPO"
      },
      "tag_values": {
        "@@assign": ["5", "60", "240"]
      }
    }
  }
}
```

## Incident Response Workflow

During a disaster incident, responders use the tagging system to:

1. **Identify Priority Assets**
   ```bash
   # Get list of high-criticality resources needing immediate recovery
   ./scripts/bia/tag_resources_by_criticality.sh \
     --query \
     --criticality High \
     --format json > incident_priority_list.json
   ```

2. **Determine Recovery Order**
   - Process `Criticality=High` resources first
   - Within each criticality, sort by RTO (shortest first)
   - Coordinate with business owners for confirmation

3. **Execute Recovery**
   ```bash
   # Initiate DRS failover for high-criticality servers
   ./scripts/recovery/initiate_drs_failover.sh \
     --resource-group High-Criticality-Production \
     --confirm
   ```

4. **Validate Recovery**
   ```bash
   # Validate recovered resources
   ./scripts/testing/validate_backup_integrity.sh \
     --criticality High
   ```

## Cost Implications

- **Resource Tagging API:** Free (first 1 million requests/month)
- **Resource Groups:** Free
- **Tag Policies:** Free (part of AWS Organizations)
- **Automated Tagging Scripts:** No direct cost (uses AWS CLI)

## Monitoring Tag Compliance

### CloudWatch Metric for Untagged Resources

Create a custom metric that tracks the percentage of production resources without criticality tags:

```bash
./scripts/monitoring/create_mtd_alarm.sh \
  --metric-name UntaggedProductionResources \
  --namespace DR/Compliance \
  --threshold 5 \
  --comparison GreaterThanThreshold \
  --description "Alert when >5% of production resources lack criticality tags"
```

## References

- [AWS Resource Groups Tagging API](https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/Welcome.html)
- [AWS Resource Groups](https://docs.aws.amazon.com/arg/latest/userguide/what-is-resource-groups.html)
- [AWS Tag Policies](https://docs.aws.amazon.com/organizations/latest/userguide/tag-policies.html)
- [NIST SP 800-34 BIA Guidelines](https://csrc.nist.gov/publications/detail/sp/800-34/rev-1/final)
