variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
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
  description = "Default tags to apply to DR resources"
  type = map(object({
    resource_arn = string
    value        = string
  }))
  default = {}
}
