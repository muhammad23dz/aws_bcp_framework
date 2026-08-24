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
  region = var.aws_region
}

# Resource Group for High-Criticality Production Resources
resource "aws_resourcegroups_group" "high_criticality_production" {
  name        = "High-Criticality-Production"
  description = "High criticality production resources for DR priority"

  resource_query {
    type = "TAG_FILTERS_1_0"
    query = jsonencode({
      ResourceTypeFilters = var.resource_type_filters
      TagFilters = [
        {
          Key = "Criticality"
          Values = ["High"]
        },
        {
          Key = "Environment"
          Values = ["Production"]
        }
      ]
    })
  }

  tags = {
    Purpose = "DR-ResourceGroup"
    Criticality = "High"
  }
}

# Resource Group for Warm Standby Infrastructure
resource "aws_resourcegroups_group" "warm_standby_infrastructure" {
  name        = "Warm-Standby-Infrastructure"
  description = "Warm standby infrastructure for DR drills"

  resource_query {
    type = "TAG_FILTERS_1_0"
    query = jsonencode({
      ResourceTypeFilters = [
        "AWS::AutoScaling::AutoScalingGroup",
        "AWS::EC2::LaunchTemplate",
        "AWS::EC2::SecurityGroup",
        "AWS::EC2::VPC"
      ]
      TagFilters = [
        {
          Key = "Purpose"
          Values = ["DR-WarmStandby"]
        }
      ]
    })
  }

  tags = {
    Purpose = "DR-ResourceGroup"
  }
}

# Tagging Policy for DR Resources
resource "aws_resourcegroups_tagging_resource" "example" {
  for_each = var.default_tags

  resource_arn = each.value.resource_arn
  tags = {
    (each.key) = each.value.value
  }
}
