output "high_criticality_group_arn" {
  description = "ARN of the high-criticality production resource group"
  value       = aws_resourcegroups_group.high_criticality_production.arn
}

output "warm_standby_group_arn" {
  description = "ARN of the warm standby infrastructure resource group"
  value       = aws_resourcegroups_group.warm_standby_infrastructure.arn
}
