output "sns_topic_arn" {
  description = "ARN of the SNS topic for DR alerts"
  value       = aws_sns_topic.dr_alerts.arn
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=DR-Monitoring"
}

output "alarm_names" {
  description = "List of created alarm names"
  value = [
    aws_cloudwatch_metric_alarm.primary_region_health_mtd_high.alarm_name,
    aws_cloudwatch_metric_alarm.primary_region_health_mtd_medium.alarm_name,
    aws_cloudwatch_metric_alarm.drs_replication_lag_high.alarm_name,
    aws_cloudwatch_metric_alarm.s3_replication_latency.alarm_name,
    aws_cloudwatch_metric_alarm.rds_snapshot_age.alarm_name,
    aws_cloudwatch_metric_alarm.warm_standby_scale_up.alarm_name
  ]
}
