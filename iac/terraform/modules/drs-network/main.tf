terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.primary_region
  alias  = "primary"
}

provider "aws" {
  region = var.dr_region
  alias  = "dr"
}

# DR Region VPC for Staging Area
resource "aws_vpc" "dr_vpc" {
  provider = aws.dr
  cidr_block           = var.dr_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "DR-Staging-VPC"
    Purpose     = "DR-Staging"
    Environment = var.environment
  }
}

# DR Region Subnet for Staging Area
resource "aws_subnet" "dr_staging_subnet" {
  provider = aws.dr
  vpc_id     = aws_vpc.dr_vpc.id
  cidr_block = var.dr_subnet_cidr

  tags = {
    Name        = "DR-Staging-Subnet"
    Purpose     = "DR-Staging"
    Environment = var.environment
  }
}

# KMS Key for DR Region Encryption
resource "aws_kms_key" "dr_encryption" {
  provider = aws.dr
  description = "KMS key for DR region encryption"

  tags = {
    Purpose = "DR-Encryption"
  }
}

resource "aws_kms_alias" "dr_encryption" {
  provider = aws.dr
  name          = "alias/dr-encryption-key"
  target_key_id = aws_kms_key.dr_encryption.id
}

# DRS Source Server (mock resource - actual DRS requires agent installation)
# This represents the configuration for DRS source server
resource "aws_drs_source_server" "primary" {
  provider = aws.primary
  
  # Note: Actual DRS source server requires agent installation on EC2 instance
  # This is a placeholder for the Terraform resource
  # In practice, you would use the DRS agent on your EC2 instances
  
  tags = {
    Criticality = var.criticality
    RTO         = var.rto
    RPO         = var.rpo
    DR-Region   = var.dr_region
    Purpose     = "DR-Source"
  }
}

# DRS Replication Configuration Template
resource "aws_drs_replication_configuration_template" "main" {
  provider = aws.primary
  
  source_server_id = var.source_server_id
  # Note: This is a simplified representation
  # Actual DRS replication configuration requires more parameters
  
  tags = {
    Purpose = "DR-Replication"
  }
}

# DRS Launch Configuration Template
resource "aws_drs_launch_configuration_template" "main" {
  provider = aws.dr
  
  # Launch configuration for recovery instances
  # This configures how instances are launched during failover
  
  tags = {
    Purpose = "DR-Recovery"
  }
}

# Security Group for DR Staging Area
resource "aws_security_group" "dr_staging" {
  provider = aws.dr
  name        = "dr-staging-sg"
  description = "Security group for DR staging area"
  vpc_id      = aws_vpc.dr_vpc.id

  # Allow necessary traffic for DRS replication
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.primary_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "DR-Staging-SG"
    Purpose     = "DR-Staging"
    Environment = var.environment
  }
}
