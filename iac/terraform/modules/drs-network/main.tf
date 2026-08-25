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
  provider             = aws.dr
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
  provider   = aws.dr
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
  provider                = aws.dr
  description             = "KMS key for DR region encryption"
  enable_key_rotation     = true # FIX: rotate annually for security best practice
  deletion_window_in_days = 14   # FIX: explicit safe deletion window (7-30 days)

  tags = {
    Purpose = "DR-Encryption"
  }
}

resource "aws_kms_alias" "dr_encryption" {
  provider      = aws.dr
  name          = "alias/dr-encryption-key"
  target_key_id = aws_kms_key.dr_encryption.id
}

# DRS Source Server - read via data source
# NOTE: aws_drs_source_server cannot be *created* by Terraform. DRS source
# servers are registered automatically when the DRS agent is installed and
# activated on an EC2 instance. We look it up here so other resources can
# reference its attributes (e.g. the source server ID).
# If var.source_server_id is empty (before agent installation), this block
# is intentionally kept as documentation only and should be uncommented once
# the agent is installed.
#
# data "aws_drs_source_server" "primary" {
#   provider         = aws.primary
#   source_server_id = var.source_server_id
# }

# DRS Replication Configuration Template
# NOTE: aws_drs_replication_configuration_template requires several mandatory
# arguments (replication_server_instance_type, staging_area_subnet_id,
# use_dedicated_replication_server, etc.) that are environment-specific.
# Configure this resource directly in the environment layer (envs/sandbox)
# once the DRS staging subnet is known, rather than in this shared module.

# DRS Launch Configuration Template
# NOTE: There is no native "aws_drs_launch_configuration_template" in the official
# Terraform AWS provider. Manage DRS launch settings via the AWS console, CLI,
# or custom null_resource script calls.
#
# resource "aws_drs_launch_configuration_template" "main" {
#   provider = aws.dr
#
#   # Launch configuration for recovery instances
#   # Configures how instances are launched during failover
#
#   tags = {
#     Purpose = "DR-Recovery"
#   }
# }

# Security Group for DR Staging Area
resource "aws_security_group" "dr_staging" {
  provider    = aws.dr
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
