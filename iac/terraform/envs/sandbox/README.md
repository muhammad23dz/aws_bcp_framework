# Sandbox Environment

This directory contains the Terraform configuration for the sandbox environment of the AWS BCP Framework.

## Prerequisites

1. **AWS Account**: A sandbox AWS account for testing
2. **Terraform**: Version 1.0 or higher installed
3. **AWS CLI**: Configured with appropriate credentials
4. **S3 Bucket**: For Terraform state storage
5. **DynamoDB Table**: For Terraform state locking

## Setup

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your values:
   ```hcl
   account_id              = "123456789012"
   ami_id                  = "ami-0abcdef1234567890"
   terraform_state_bucket  = "my-terraform-state-bucket"
   terraform_lock_table   = "my-terraform-lock-table"
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Review the plan:
   ```bash
   terraform plan
   ```

5. Apply the configuration:
   ```bash
   terraform apply
   ```

## Modules Used

- **tagging-baseline**: Resource groups and tagging configuration
- **s3-cross-region-replication**: S3 buckets with cross-region replication
- **drs-network**: DRS network infrastructure in DR region
- **warm-standby-asg**: Auto Scaling Group for warm standby

## Cost Estimates

This sandbox configuration is designed to minimize costs:
- S3 buckets: Minimal storage costs
- Warm standby ASG: Scaled to 0 (no running instances)
- DRS: Minimal replication costs for small data volumes

Estimated monthly cost: **$5-20** (depending on data volume)

## Teardown

To remove all sandbox resources:
```bash
terraform destroy
```

## Outputs

After successful deployment, the following outputs will be available:
- Tagging baseline resource group ARNs
- S3 bucket names and ARNs
- DRS network configuration
- Warm standby ASG details
