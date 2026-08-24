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
  region = var.dr_region
}

# DR Region VPC for Warm Standby
resource "aws_vpc" "dr_warm_standby_vpc" {
  cidr_block           = var.dr_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "DR-WarmStandby-VPC"
    Purpose     = "DR-WarmStandby"
    Environment = var.environment
  }
}

# DR Region Subnets for Warm Standby
resource "aws_subnet" "dr_warm_standby_subnet" {
  vpc_id     = aws_vpc.dr_warm_standby_vpc.id
  cidr_block = var.dr_subnet_cidr

  tags = {
    Name        = "DR-WarmStandby-Subnet"
    Purpose     = "DR-WarmStandby"
    Environment = var.environment
  }
}

# Launch Template for Warm Standby
resource "aws_launch_template" "warm_standby" {
  name_prefix   = "dr-warm-standby-"
  description   = "Launch template for DR warm standby instances"
  image_id      = var.ami_id
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = false
    subnet_id                   = aws_subnet.dr_warm_standby_subnet.id
    security_groups             = [aws_security_group.warm_standby.id]
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "DR-WarmStandby-Instance"
      Purpose     = "DR-WarmStandby"
      Criticality = var.criticality
      Environment = var.environment
    }
  }

  tags = {
    Purpose = "DR-WarmStandby"
  }
}

# Security Group for Warm Standby
resource "aws_security_group" "warm_standby" {
  name        = "dr-warm-standby-sg"
  description = "Security group for DR warm standby instances"
  vpc_id      = aws_vpc.dr_warm_standby_vpc.id

  # Allow necessary application traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "DR-WarmStandby-SG"
    Purpose     = "DR-WarmStandby"
    Environment = var.environment
  }
}

# Warm Standby Auto Scaling Group
resource "aws_autoscaling_group" "warm_standby" {
  name                = "dr-warm-standby-asg"
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = [aws_subnet.dr_warm_standby_subnet.id]

  launch_template {
    id      = aws_launch_template.warm_standby.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = var.health_check_grace_period

  tag {
    key                 = "Purpose"
    value               = "DR-WarmStandby"
    propagate_at_launch = true
  }

  tag {
    key                 = "Criticality"
    value               = var.criticality
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# CloudWatch Alarm for Scale-Up
resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "dr-warm-standby-scale-up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupInServiceInstances"
  alarm_description   = "Alarm when warm standby ASG scales up"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 1

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.warm_standby.name
  }

  alarm_actions = [aws_sns_topic.dr_alerts.arn]
  ok_actions    = [aws_sns_topic.dr_alerts.arn]

  tags = {
    Purpose = "DR-Monitoring"
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "dr_alerts" {
  name = "DR-WarmStandby-Alerts"

  tags = {
    Purpose = "DR-Notifications"
  }
}
