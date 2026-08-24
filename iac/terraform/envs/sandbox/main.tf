terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = var.terraform_state_bucket
    key            = "aws-bcp-framework/sandbox/terraform.tfstate"
    region         = var.primary_region
    encrypt        = true
    dynamodb_table = var.terraform_lock_table
  }
}

provider "aws" {
  region = var.primary_region
  default_tags {
    tags = {
      Project     = "AWS-BCP-Framework"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Tagging Baseline Module
module "tagging_baseline" {
  source = "../../../modules/tagging-baseline"

  aws_region            = var.primary_region
  resource_type_filters = var.resource_type_filters
  default_tags          = var.default_tags
}

# S3 Cross-Region Replication Module
module "s3_crr" {
  source = "../../../modules/s3-cross-region-replication"

  primary_region = var.primary_region
  dr_region      = var.dr_region
  bucket_prefix  = "${var.project_name}-sandbox"
  account_id     = var.account_id
  criticality    = "Medium"
  rto            = 4
  rpo            = 60
  environment    = var.environment
}

# DRS Network Module
module "drs_network" {
  source = "../../../modules/drs-network"

  primary_region    = var.primary_region
  dr_region         = var.dr_region
  primary_vpc_cidr  = var.primary_vpc_cidr
  dr_vpc_cidr       = var.dr_vpc_cidr
  dr_subnet_cidr   = var.dr_subnet_cidr
  source_server_id  = var.source_server_id
  criticality       = "Medium"
  rto               = 4
  rpo               = 60
  environment       = var.environment
}

# Warm Standby ASG Module
module "warm_standby" {
  source = "../../../modules/warm-standby-asg"

  dr_region                 = var.dr_region
  dr_vpc_cidr              = var.warm_standby_vpc_cidr
  dr_subnet_cidr           = var.warm_standby_subnet_cidr
  ami_id                   = var.ami_id
  instance_type            = var.instance_type
  min_size                 = 0
  max_size                 = 5
  desired_capacity         = 0
  health_check_grace_period = 300
  allowed_cidr             = var.allowed_cidr
  criticality              = "Medium"
  environment              = var.environment
}
