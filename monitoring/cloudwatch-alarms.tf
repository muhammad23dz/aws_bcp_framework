terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# SNS Topic for DR Alerts
resource "aws_sns_topic" "dr_alerts" {
  name = "DR-Alerts"

  tags = {
    Purpose = "DR-Notifications"
  }
}

# SNS Topic Subscription for Email
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# SNS Topic Subscription for Slack (optional)
resource "aws_sns_topic_subscription" "slack_alert" {
  count      = var.slack_webhook_url != "" ? 1 : 0
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# MTD Alarm: Primary Region Health Check Failure Duration (High Criticality)
resource "aws_cloudwatch_metric_alarm" "primary_region_health_mtd_high" {
  alarm_name          = "DR-MTD-PrimaryRegionHealth-High"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PrimaryRegionHealthCheckFailureDuration"
  namespace           = "DR"
  period              = 60
  statistic           = "Maximum"
  threshold           = 3600  # MTD - RTO = 7200 - 3600
  alarm_description   = "Alert when primary region health failure duration exceeds MTD-RTO buffer for high-criticality resources"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  ok_actions          = [aws_sns_topic.dr_alerts.arn]

  tags = {
    Criticality = "High"
    Purpose     = "DR-Monitoring"
  }
}

# MTD Alarm: Primary Region Health Check Failure Duration (Medium Criticality)
resource "aws_cloudwatch_metric_alarm" "primary_region_health_mtd_medium" {
  alarm_name          = "DR-MTD-PrimaryRegionHealth-Medium"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PrimaryRegionHealthCheckFailureDuration"
  namespace           = "DR"
  period              = 60
  statistic           = "Maximum"
  threshold           = 14400  # MTD - RTO = 28800 - 14400
  alarm_description   = "Alert when primary region health failure duration exceeds MTD-RTO buffer for medium-criticality resources"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  ok_actions          = [aws_sns_topic.dr_alerts.arn]

  tags = {
    Criticality = "Medium"
    Purpose     = "DR-Monitoring"
  }
}

# DRS Replication Lag Alarm (High Criticality)
resource "aws_cloudwatch_metric_alarm" "drs_replication_lag_high" {
  alarm_name          = "DR-DRS-ReplicationLag-High"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TimeSinceLastSuccessfulReplication"
  namespace           = "AWS/DRS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 300  # RPO target
  alarm_description   = "Alert when DRS replication lag exceeds RPO target for high-criticality resources"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  ok_actions          = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    SourceServerID = var.drs_source_server_id
  }

  tags = {
    Criticality = "High"
    Purpose     = "DR-Monitoring"
  }
}

# S3 Replication Latency Alarm
resource "aws_cloudwatch_metric_alarm" "s3_replication_latency" {
  alarm_name          = "DR-S3-ReplicationLatency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ReplicationLatency"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Maximum"
  threshold           = 900  # RPO target
  alarm_description   = "Alert when S3 cross-region replication latency exceeds RPO target"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  ok_actions          = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    BucketName = var.s3_bucket_name
  }

  tags = {
    Purpose = "DR-Monitoring"
  }
}

# RDS Snapshot Age Alarm
resource "aws_cloudwatch_metric_alarm" "rds_snapshot_age" {
  alarm_name          = "DR-RDS-SnapshotAge"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SnapshotAge"
  namespace           = "DR"
  period              = 300
  statistic           = "Maximum"
  threshold           = 300  # RPO target
  alarm_description   = "Alert when RDS snapshot age exceeds RPO target"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  ok_actions          = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = {
    Purpose = "DR-Monitoring"
  }
}

# Warm Standby ASG Scale-Up Alarm
resource "aws_cloudwatch_metric_alarm" "warm_standby_scale_up" {
  alarm_name          = "DR-WarmStandby-ScaleUp"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert when warm standby ASG scales up (drill or failover)"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  ok_actions          = [aws_sns_topic.dr_alerts.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  tags = {
    Purpose = "DR-Monitoring"
  }
}

# CloudWatch Dashboard for DR Monitoring
resource "aws_cloudwatch_dashboard" "dr_monitoring" {
  dashboard_name = "DR-Monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type  = "metric"
        x     = 0
        y     = 0
        width = 12
        height = 6
        properties = {
          metrics = [
            ["DR", "PrimaryRegionHealthCheckFailureDuration", {"region": var.aws_region}]
          ]
          period   = 60
          stat     = "Maximum"
          region   = var.aws_region
          title    = "Primary Region Health Failure Duration"
        }
      },
      {
        type  = "metric"
        x     = 0
        y     = 6
        width = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/DRS", "TimeSinceLastSuccessfulReplication", {"region": var.dr_region}]
          ]
          period   = 300
          stat     = "Maximum"
          region   = var.dr_region
          title    = "DRS Replication Lag"
        }
      },
      {
        type  = "metric"
        x     = 0
        y     = 12
        width = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "ReplicationLatency", {"region": var.dr_region}]
          ]
          period   = 300
          stat     = "Maximum"
          region   = var.dr_region
          title    = "S3 Replication Latency"
        }
      },
      {
        type  = "alarm"
        x     = 0
        y     = 18
        width = 24
        height = 3
        properties = {
          title  = "DR Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.primary_region_health_mtd_high.alarm_name,
            aws_cloudwatch_metric_alarm.drs_replication_lag_high.alarm_name,
            aws_cloudwatch_metric_alarm.s3_replication_latency.alarm_name
          ]
        }
      }
    ]
  })
}
