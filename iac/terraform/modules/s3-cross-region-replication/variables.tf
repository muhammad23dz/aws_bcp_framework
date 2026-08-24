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

variable "bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
  default     = ""
}

variable "criticality" {
  description = "Criticality level for tagging"
  type        = string
  default     = "High"
  validation {
    condition     = contains(["High", "Medium", "Low"], var.criticality)
    error_message = "Criticality must be High, Medium, or Low."
  }
}

variable "rto" {
  description = "Recovery Time Objective in hours"
  type        = number
  default     = 1
}

variable "rpo" {
  description = "Recovery Point Objective in minutes"
  type        = number
  default     = 5
}

variable "environment" {
  description = "Environment tag value"
  type        = string
  default     = "Production"
}
