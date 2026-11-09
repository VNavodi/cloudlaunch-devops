mock_provider "aws" {}

override_data {
  target = data.aws_instance.cloudlaunch
  values = { id = "i-0b469c30aee75c370" }
}

run "disabled_by_default" {
  command = plan
  assert {
    condition     = length(aws_cloudwatch_log_group.application) == 0 && length(aws_cloudwatch_metric_alarm.health) == 0 && length(aws_cloudwatch_metric_alarm.cpu) == 0 && length(aws_cloudwatch_metric_alarm.instance_status) == 0
    error_message = "Monitoring must not be provisioned by default."
  }
}

run "approved_monitoring_design" {
  command = plan
  variables { enable_monitoring = true }
  assert {
    condition     = aws_cloudwatch_log_group.application[0].retention_in_days == 14
    error_message = "Retention must be bounded."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.health[0].treat_missing_data == "missing" && aws_cloudwatch_metric_alarm.health[0].threshold == 1
    error_message = "Missing health must not mean healthy."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu[0].dimensions.InstanceId == "i-0b469c30aee75c370" && length(aws_cloudwatch_metric_alarm.cpu[0].alarm_actions) == 0
    error_message = "Only the existing instance is monitored; notifications default off."
  }
}
