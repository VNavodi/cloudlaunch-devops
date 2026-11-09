# Optional NEW resources only. Inventory remains read-only with the default false.
variable "enable_monitoring" {
  description = "Enable only after account inventory, cost review and explicit apply approval."
  type        = bool
  default     = false
}

variable "monitoring_alarm_actions" {
  description = "Approved existing SNS topic ARNs; empty means alarms have no notifications."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for arn in var.monitoring_alarm_actions : can(regex("^arn:aws:sns:ap-southeast-2:636621822646:[A-Za-z0-9_-]+$", arn))])
    error_message = "Only CloudLaunch Sydney SNS topic ARNs are permitted."
  }
}

resource "aws_cloudwatch_log_group" "application" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/cloudlaunch/application"
  retention_in_days = 14
  lifecycle { prevent_destroy = true }
  tags = { Project = "CloudLaunch" }
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "cloudlaunch-ec2-status"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "missing"
  dimensions          = { InstanceId = data.aws_instance.cloudlaunch.id }
  alarm_actions       = var.monitoring_alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "cloudlaunch-ec2-cpu"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "missing"
  dimensions          = { InstanceId = data.aws_instance.cloudlaunch.id }
  alarm_actions       = var.monitoring_alarm_actions
}

# Explicit JSON health events from the opt-in host health timer, not inferred from CPU.
resource "aws_cloudwatch_log_metric_filter" "health" {
  count          = var.enable_monitoring ? 1 : 0
  name           = "cloudlaunch-health"
  log_group_name = aws_cloudwatch_log_group.application[0].name
  pattern        = "{ $.event = \"health_probe\" }"
  metric_transformation {
    name      = "Healthy"
    namespace = "CloudLaunch"
    value     = "$.healthy"
  }
}

resource "aws_cloudwatch_metric_alarm" "health" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "cloudlaunch-api-health"
  namespace           = "CloudLaunch"
  metric_name         = "Healthy"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "missing"
  alarm_actions       = var.monitoring_alarm_actions
}
