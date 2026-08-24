output "dr_vpc_id" {
  description = "ID of the DR warm standby VPC"
  value       = aws_vpc.dr_warm_standby_vpc.id
}

output "dr_subnet_id" {
  description = "ID of the DR warm standby subnet"
  value       = aws_subnet.dr_warm_standby_subnet.id
}

output "asg_name" {
  description = "Name of the warm standby ASG"
  value       = aws_autoscaling_group.warm_standby.name
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.warm_standby.id
}

output "security_group_id" {
  description = "ID of the warm standby security group"
  value       = aws_security_group.warm_standby.id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.dr_alerts.arn
}
