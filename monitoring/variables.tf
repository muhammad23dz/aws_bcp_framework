variable "aws_region" {
  description = "AWS region for monitoring"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "DR AWS region"
  type        = string
  default     = "us-west-2"
}

variable "alert_email" {
  description = "Email address for DR alerts"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for DR alerts (optional)"
  type        = string
  default     = ""
}

variable "drs_source_server_id" {
  description = "DRS source server ID for replication monitoring"
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "S3 bucket name for replication monitoring"
  type        = string
  default     = ""
}

variable "rds_instance_id" {
  description = "RDS instance ID for snapshot monitoring"
  type        = string
  default     = ""
}

variable "asg_name" {
  description = "Auto Scaling Group name for warm standby monitoring"
  type        = string
  default     = ""
}
