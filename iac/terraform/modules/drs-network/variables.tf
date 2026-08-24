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

variable "primary_vpc_cidr" {
  description = "CIDR block of primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dr_vpc_cidr" {
  description = "CIDR block for DR VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "dr_subnet_cidr" {
  description = "CIDR block for DR staging subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "source_server_id" {
  description = "ID of the source server for DRS"
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
