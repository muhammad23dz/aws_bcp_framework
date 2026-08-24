# DRP Testing Checklist

This checklist validates the disaster recovery framework through automated and manual tests. Most items are backed by scripts for repeatability.

## Pre-Test Prerequisites

- [ ] AWS CLI configured with appropriate credentials
- [ ] Terraform installed and initialized
- [ ] Required environment variables set (AWS_PROFILE, SANDBOX_ACCOUNT_ID, etc.)
- [ ] Scripts have execute permissions (`chmod +x scripts/**/*.sh`)

## Phase 1: Governance Validation

### SCP Deployment
- [ ] **Scripted:** Deploy data residency SCP with `--dry-run`
  ```bash
  ./scripts/governance/deploy_scp.sh --policy-file policies/scp-data-residency.json --ou-id <ou-id> --dry-run
  ```
- [ ] **Scripted:** Deploy backup protection SCP with `--dry-run`
  ```bash
  ./scripts/governance/deploy_scp.sh --policy-file policies/scp-deny-non-dr-regions.json --ou-id <ou-id> --dry-run
  ```
- [ ] **Manual:** Verify SCP syntax with `jq empty policies/scp-*.json`
- [ ] **Manual:** Review SCP policy documents for compliance requirements

### Permission Boundary Validation
- [ ] **Manual:** Review permission boundary policy in `policies/permission-boundary-dr-ops.json`
- [ ] **Manual:** Verify permission boundary denies SCP modification
- [ ] **Manual:** Verify permission boundary denies backup deletion
- [ ] **Manual:** Verify permission boundary allows DRS operations with conditions

## Phase 2: BIA & Criticality Validation

### Resource Tagging
- [ ] **Scripted:** Tag resources with high criticality
  ```bash
  ./scripts/bia/tag_resources_by_criticality.sh --criticality High --rto 1 --rpo 5 --dr-region us-west-2 --resource-ids i-1234567890abcdef0 --dry-run
  ```
- [ ] **Scripted:** Query high-criticality resources
  ```bash
  ./scripts/bia/tag_resources_by_criticality.sh --query --criticality High --environment Production
  ```
- [ ] **Scripted:** Tag resources with medium criticality
  ```bash
  ./scripts/bia/tag_resources_by_criticality.sh --criticality Medium --rto 4 --rpo 60 --dr-region us-west-2 --resource-ids sg-abcdef123456 --dry-run
  ```
- [ ] **Manual:** Verify resource groups created via Terraform
  ```bash
  aws resourcegroups list-groups --query "Groups[?Name=='High-Criticality-Production']"
  ```

### Tag Compliance
- [ ] **Manual:** Verify all production resources have Criticality tag
- [ ] **Manual:** Verify all production resources have RTO and RPO tags
- [ ] **Manual:** Verify all production resources have DR-Region tag

## Phase 3: Infrastructure Validation

### Terraform Validation
- [ ] **Scripted:** Validate all Terraform modules
  ```bash
  cd iac/terraform/modules/tagging-baseline && terraform validate
  cd iac/terraform/modules/s3-cross-region-replication && terraform validate
  cd iac/terraform/modules/drs-network && terraform validate
  cd iac/terraform/modules/warm-standby-asg && terraform validate
  cd iac/terraform/envs/sandbox && terraform validate
  ```
- [ ] **Scripted:** Format check all Terraform modules
  ```bash
  terraform fmt -check -recursive iac/terraform/
  ```
- [ ] **Scripted:** Plan sandbox environment
  ```bash
  cd iac/terraform/envs/sandbox
  terraform plan -var="account_id=<SANDBOX_ACCOUNT_ID>" -var="ami_id=<AMI_ID>"
  ```

### S3 Cross-Region Replication
- [ ] **Manual:** Verify S3 buckets created with versioning enabled
- [ ] **Manual:** Verify S3 buckets have encryption enabled
- [ ] **Manual:** Verify replication configuration is active
- [ ] **Scripted:** Validate S3 object count between primary and replica
  ```bash
  ./scripts/testing/validate_backup_integrity.sh --source-bucket <primary-bucket> --destination-bucket <replica-bucket> --check-type object-count
  ```
- [ ] **Scripted:** Validate S3 checksums between primary and replica
  ```bash
  ./scripts/testing/validate_backup_integrity.sh --source-bucket <primary-bucket> --destination-bucket <replica-bucket> --check-type checksum --sample-size 50
  ```

### DRS Network Configuration
- [ ] **Manual:** Verify DR VPC created in DR region
- [ ] **Manual:** Verify DR subnet created with correct CIDR
- [ ] **Manual:** Verify KMS key created for DR encryption
- [ ] **Manual:** Verify security group allows only necessary traffic

### Warm Standby ASG
- [ ] **Manual:** Verify ASG created with desired capacity 0
- [ ] **Manual:** Verify launch template configured correctly
- [ ] **Manual:** Verify security group blocks production CIDR
- [ ] **Scripted:** Test ASG scale-up within RTO target
  ```bash
  START_TIME=$(date +%s)
  ./scripts/recovery/deploy_hot_site.sh --asg-name dr-warm-standby-asg --capacity 2 --dr-region us-west-2 --confirm
  # Wait for instances to be healthy
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  if [ $DURATION -lt 3600 ]; then echo "PASS: Scale-up within RTO"; else echo "FAIL"; fi
  ```

## Phase 4: Monitoring Validation

### CloudWatch Alarms
- [ ] **Scripted:** Create MTD alarm for primary region health
  ```bash
  ./scripts/monitoring/create_mtd_alarm.sh --alarm-name DR-MTD-PrimaryHealth --metric-name PrimaryRegionHealthCheckFailureDuration --namespace DR --threshold 3600 --dry-run
  ```
- [ ] **Scripted:** Create DRS replication lag alarm
  ```bash
  ./scripts/monitoring/create_mtd_alarm.sh --alarm-name DR-DRS-ReplicationLag --metric-name TimeSinceLastSuccessfulReplication --namespace AWS/DRS --threshold 300 --dry-run
  ```
- [ ] **Manual:** Verify SNS topic created for notifications
- [ ] **Manual:** Verify CloudWatch dashboard created
- [ ] **Manual:** Verify alarm thresholds match RTO/RPO targets

### Alarm Testing
- [ ] **Scripted:** Simulate alarm state (test notification)
  ```bash
  aws cloudwatch put-metric-data --namespace DR --metric-data '[{"MetricName":"PrimaryRegionHealthCheckFailureDuration","Value":4000,"Unit":"Seconds"}]'
  ```
- [ ] **Manual:** Verify alarm state changes to ALARM
- [ ] **Manual:** Verify SNS notification received
- [ ] **Scripted:** Reset alarm to OK state
  ```bash
  aws cloudwatch set-alarm-state --alarm-name DR-MTD-PrimaryHealth --state-value OK --state-reason "Test completed"
  ```

## Phase 5: Drill Testing

### Warm Standby Scale-Up Test
- [ ] **Scripted:** Scale up warm standby ASG
  ```bash
  ./scripts/recovery/deploy_hot_site.sh --asg-name dr-warm-standby-asg --capacity 2 --dr-region us-west-2 --dry-run
  ```
- [ ] **Scripted:** Verify scale-up completes within target RTO
  ```bash
  # Time the scale-up operation and assert against threshold
  ```
- [ ] **Manual:** Verify instances pass health checks
- [ ] **Manual:** Verify instances are accessible in DR VPC
- [ ] **Scripted:** Scale down ASG after test
  ```bash
  ./scripts/recovery/deploy_hot_site.sh --asg-name dr-warm-standby-asg --capacity 0 --dr-region us-west-2 --confirm
  ```

### Drill Instance Launch
- [ ] **Scripted:** Launch drill instance with dry-run
  ```bash
  ./scripts/testing/launch_drill_instance.sh --ami-id <ami-id> --instance-type t3.micro --dr-region us-west-2 --subnet-id <subnet-id> --security-group-id <sg-id> --dry-run
  ```
- [ ] **Scripted:** Launch drill instance with confirm
  ```bash
  ./scripts/testing/launch_drill_instance.sh --ami-id <ami-id> --instance-type t3.micro --dr-region us-west-2 --subnet-id <subnet-id> --security-group-id <sg-id> --confirm
  ```
- [ ] **Manual:** Verify instance boots successfully
- [ ] **Manual:** Verify instance has correct tags (Purpose=DR-Drill)
- [ ] **Manual:** Verify instance is in isolated VPC

### Network Isolation Verification
- [ ] **Scripted:** Verify security group blocks production CIDR
  ```bash
  aws ec2 describe-security-groups --group-ids <drill-sg> --region us-west-2 --query 'SecurityGroups[0].IpPermissions[?contains(IpRanges[].CidrIp, `10.0.0.0/16`)]'
  ```
- [ ] **Scripted:** Verify no routes to production VPC
  ```bash
  aws ec2 describe-route-tables --route-table-ids <drill-rtb> --region us-west-2 --query 'RouteTables[0].Routes[?contains(DestinationCidrBlock, `10.0.0.0/16`)]'
  ```
- [ ] **Scripted:** Verify no VPC peering to production
  ```bash
  aws ec2 describe-vpc-peering-connections --region us-west-2 --query 'VpcPeeringConnections[?AccepterVpcInfo.VpcId==`<production-vpc-id>`]'
  ```
- [ ] **Manual:** Verify DNS resolution limited to DR region

### Data Integrity Validation
- [ ] **Scripted:** Validate S3 checksums
  ```bash
  ./scripts/testing/validate_backup_integrity.sh --source-bucket <primary-bucket> --destination-bucket <replica-bucket> --check-type checksum --sample-size 100
  ```
- [ ] **Scripted:** Validate S3 object counts
  ```bash
  ./scripts/testing/validate_backup_integrity.sh --source-bucket <primary-bucket> --destination-bucket <replica-bucket> --check-type object-count
  ```
- [ ] **Scripted:** Validate RDS row counts (if applicable)
  ```bash
  ./scripts/testing/validate_backup_integrity.sh --source-db <primary-db> --destination-db <replica-db> --check-type row-count --table-name <table-name>
  ```
- [ ] **Manual:** Verify replication lag is within RPO target

### Drill Teardown
- [ ] **Scripted:** Teardown drill instance
  ```bash
  ./scripts/testing/launch_drill_instance.sh --teardown --drill-id <drill-instance-id> --dr-region us-west-2 --confirm
  ```
- [ ] **Scripted:** Verify no orphaned drill resources
  ```bash
  aws resourcegroupsstaggingapi get-resources --tag-filters Key=Purpose,Values=DR-Drill --resources-per-page 100
  ```
- [ ] **Scripted:** Verify no drill instances running
  ```bash
  aws ec2 describe-instances --filters Name=tag:Purpose,Values=DR-Drill --region us-west-2 --query 'Reservations[].Instances[?State.Name!=`terminated`]'
  ```
- [ ] **Manual:** Verify no drill volumes remaining
- [ ] **Manual:** Verify cost impact of drill

## Phase 6: DRS Failover Test (Optional)

### Pre-Failover Checks
- [ ] **Scripted:** Check DRS agent status
  ```bash
  # Integrated in initiate_drs_failover.sh
  ```
- [ ] **Scripted:** Check replication status
  ```bash
  # Integrated in initiate_drs_failover.sh
  ```
- [ ] **Manual:** Verify staging area has sufficient capacity

### Failover Execution
- [ ] **Scripted:** Initiate DRS failover with dry-run
  ```bash
  ./scripts/recovery/initiate_drs_failover.sh --source-server-id <source-server-id> --dr-region us-west-2 --dry-run
  ```
- [ ] **Scripted:** Initiate DRS failover with confirm (drill mode)
  ```bash
  ./scripts/recovery/initiate_drs_failover.sh --source-server-id <source-server-id> --dr-region us-west-2 --purpose DR-Drill --confirm
  ```
- [ ] **Manual:** Verify recovery instance launches successfully
- [ ] **Manual:** Verify recovery instance boots from latest recovery point
- [ ] **Manual:** Verify recovery instance passes health checks

### Post-Failover Validation
- [ ] **Manual:** Verify data volumes attached and accessible
- [ ] **Manual:** Verify network configuration correct
- [ ] **Manual:** Verify application functionality
- [ ] **Scripted:** Initiate failback (if applicable)

## Phase 7: CI/CD Validation

### GitHub Actions Workflow
- [ ] **Manual:** Verify `.github/workflows/validate.yml` exists
- [ ] **Manual:** Verify workflow runs on pull requests
- [ ] **Manual:** Verify workflow includes terraform validate
- [ ] **Manual:** Verify workflow includes terraform fmt check
- [ ] **Manual:** Verify workflow includes shellcheck
- [ ] **Manual:** Verify workflow includes JSON schema validation

### Script Validation
- [ ] **Scripted:** Run shellcheck on all scripts
  ```bash
  shellcheck scripts/**/*.sh
  ```
- [ ] **Scripted:** Verify scripts have execute permissions
  ```bash
  find scripts/ -type f -name "*.sh" -exec chmod +x {} \;
  ```

## Phase 8: Documentation Validation

- [ ] **Manual:** Verify README.md includes architecture diagram
- [ ] **Manual:** Verify README.md includes how-to-run walkthrough
- [ ] **Manual:** Verify all documentation files exist
- [ ] **Manual:** Verify documentation is consistent with implementation
- [ ] **Manual:** Verify cost estimates documented
- [ ] **Manual:** Verify safety guardrails documented

## Phase 9: Cost Safety Validation

- [ ] **Manual:** Verify all billable resources tagged with Purpose=BCP-Demo
- [ ] **Manual:** Verify instance types are minimal (t3.micro/t3.small)
- [ ] **Manual:** Verify ASG scaled to 0 when not in drill
- [ ] **Manual:** Verify teardown scripts exist for all resource-creating scripts
- [ ] **Manual:** Verify CloudWatch budget alerts configured

## Phase 10: Security Validation

- [ ] **Manual:** Verify no hardcoded credentials in repo
- [ ] **Manual:** Verify no hardcoded account IDs in repo
- [ ] **Manual:** Verify IAM roles follow least privilege
- [ ] **Manual:** Verify S3 buckets have encryption enabled
- [ ] **Manual:** Verify security groups follow principle of least access

## Test Results Summary

| Test Category | Total Tests | Passed | Failed | Blocked |
|---|---|---|---|---|
| Governance | 6 | | | |
| BIA & Criticality | 6 | | | |
| Infrastructure | 8 | | | |
| Monitoring | 6 | | | |
| Drill Testing | 12 | | | |
| DRS Failover | 6 | | | |
| CI/CD | 5 | | | |
| Documentation | 5 | | | |
| Cost Safety | 5 | | | |
| Security | 5 | | | |
| **Total** | **64** | | | |

## Test Execution Notes

- Execute tests in order from Phase 1 to Phase 10
- Use `--dry-run` flag for all destructive operations during initial validation
- Only use `--confirm` flag after dry-run validation passes
- Document any failures with root cause analysis
- Re-run failed tests after remediation
- Maintain test results in version control for audit trail

## Automated Test Script

Run all automated tests with a single command:

```bash
#!/bin/bash
# Run all automated validation tests

echo "=== Starting Automated DRP Validation ==="

# Phase 1: Governance
echo "Phase 1: Governance Validation"
./scripts/governance/deploy_scp.sh --policy-file policies/scp-data-residency.json --ou-id <ou-id> --dry-run

# Phase 2: BIA
echo "Phase 2: BIA Validation"
./scripts/bia/tag_resources_by_criticality.sh --query --criticality High

# Phase 3: Infrastructure
echo "Phase 3: Infrastructure Validation"
cd iac/terraform/modules/tagging-baseline && terraform validate
cd iac/terraform/modules/s3-cross-region-replication && terraform validate
cd iac/terraform/modules/drs-network && terraform validate
cd iac/terraform/modules/warm-standby-asg && terraform validate

# Phase 4: Monitoring
echo "Phase 4: Monitoring Validation"
./scripts/monitoring/create_mtd_alarm.sh --alarm-name DR-MTD-PrimaryHealth --metric-name PrimaryRegionHealthCheckFailureDuration --namespace DR --threshold 3600 --dry-run

# Phase 5: Drill Testing
echo "Phase 5: Drill Testing"
./scripts/testing/validate_backup_integrity.sh --source-bucket <primary-bucket> --destination-bucket <replica-bucket> --check-type object-count

echo "=== Automated Validation Complete ==="
```
