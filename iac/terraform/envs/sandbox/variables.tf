variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "aws-bcp-framework"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "sandbox"
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "DR AWS region"
  type        = string
  default     = "us-west-2"
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
  default     = ""  # Set via TF_VAR_account_id or terraform.tfvars
}

variable "primary_vpc_cidr" {
  description = "CIDR block for primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dr_vpc_cidr" {
  description = "CIDR block for DR VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dr_subnet_cidr" {
  description = "CIDR block for DR subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "warm_standby_vpc_cidr" {
  description = "CIDR block for warm standby VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "warm_standby_subnet_cidr" {
  description = "CIDR block for warm standby subnet"
  type        = string
  default     = "10.2.1.0/24"
}

variable "source_server_id" {
  description = "Source server ID for DRS"
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "AMI ID for instances"
  type        = string
  default     = ""  # Set via TF_VAR_ami_id or terraform.tfvars
}

variable "instance_type" {
  description = "Instance type for warm standby"
  type        = string
  default     = "t3.micro"
}

variable "allowed_cidr" {
  description = "Allowed CIDR for security group ingress"
  type        = string
  default     = "10.0.0.0/16"
}

variable "resource_type_filters" {
  description = "Resource type filters for resource groups"
  type        = list(string)
  default = [
    "AWS::EC2::Instance",
    "AWS::RDS::DBInstance",
    "AWS::ElasticLoadBalancingV2::LoadBalancer",
    "AWS::Lambda::Function",
    "AWS::S3::Bucket",
    "AWS::AutoScaling::AutoScalingGroup"
  ]
}

variable "default_tags" {
  description = "Default tags to apply to resources"
  type = map(object({
    resource_arn = string
    value        = string
  }))
  default = {}
}

variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
  default     = ""  # Set via TF_VAR_terraform_state_bucket
}

variable "terraform_lock_table" {
  description = "DynamoDB table for Terraform state locking"
  type        = string
  default     = ""  # Set via TF_VAR_terraform_lock_table
}
