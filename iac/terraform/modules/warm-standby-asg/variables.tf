variable "dr_region" {
  description = "DR AWS region"
  type        = string
  default     = "us-west-2"
}

variable "dr_vpc_cidr" {
  description = "CIDR block for DR VPC"
  type        = string
  default     = "10.2.0.0/16"
}

# dr_subnet_cidrs replaces the old dr_subnet_cidr (single value). Providing
# at least 2 CIDRs is strongly recommended to span multiple AZs.
variable "dr_subnet_cidrs" {
  description = "List of CIDR blocks for DR subnets (one per AZ). Provide at least 2 for multi-AZ resiliency."
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24"]

  validation {
    condition     = length(var.dr_subnet_cidrs) >= 1
    error_message = "At least one subnet CIDR must be provided. Two or more are recommended for multi-AZ DR."
  }
}

variable "ami_id" {
  description = "AMI ID for warm standby instances. Must be a valid AMI in the DR region. No default is provided — this must be explicitly set by the caller."
  type        = string

  validation {
    condition     = length(var.ami_id) > 4 && substr(var.ami_id, 0, 4) == "ami-"
    error_message = "ami_id must be a valid AMI ID starting with 'ami-' (e.g. ami-0abcdef1234567890)."
  }
}

variable "instance_type" {
  description = "Instance type for warm standby"
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum size for ASG"
  type        = number
  default     = 0
}

variable "max_size" {
  description = "Maximum size for ASG"
  type        = number
  default     = 10
}

variable "desired_capacity" {
  description = "Desired capacity for ASG"
  type        = number
  default     = 0
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}

variable "allowed_cidr" {
  description = "Allowed CIDR for security group ingress"
  type        = string
  default     = "10.0.0.0/16"
}

variable "criticality" {
  description = "Criticality level for tagging"
  type        = string
  default     = "Medium"
  validation {
    condition     = contains(["High", "Medium", "Low"], var.criticality)
    error_message = "Criticality must be High, Medium, or Low."
  }
}

variable "environment" {
  description = "Environment tag value"
  type        = string
  default     = "Production"
}
