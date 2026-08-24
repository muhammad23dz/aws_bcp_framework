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

variable "dr_subnet_cidr" {
  description = "CIDR block for DR subnet"
  type        = string
  default     = "10.2.1.0/24"
}

variable "ami_id" {
  description = "AMI ID for warm standby instances"
  type        = string
  default     = ""
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
