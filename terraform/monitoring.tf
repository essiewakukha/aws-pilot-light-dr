# ---------------------------------------------------------------------------
# Alerting: you have to *prove* the RPO, not just assume it.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "dr_alerts" {
  provider = aws.dr
  name     = "${var.project}-dr-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  provider  = aws.dr
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Fires when replica lag reaches 2/3 of the RPO, giving you time to react
# before the RPO is actually breached.
resource "aws_cloudwatch_metric_alarm" "replica_lag_rpo" {
  provider            = aws.dr
  alarm_name          = "${var.project}-replica-lag-approaching-rpo"
  alarm_description   = "Cross-Region replica lag is approaching the ${var.rpo_seconds}s RPO."
  namespace           = "AWS/RDS"
  metric_name         = "ReplicaLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = floor(var.rpo_seconds * 2 / 3)
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching" # replication stopped = no data = bad
  dimensions          = { DBInstanceIdentifier = aws_db_instance.dr_replica.identifier }
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  ok_actions          = [aws_sns_topic.dr_alerts.arn]
}

# Route 53 health-check metrics only exist in us-east-1.
resource "aws_sns_topic" "primary_alerts" {
  count    = local.dns_enabled ? 1 : 0
  provider = aws.primary
  name     = "${var.project}-primary-alerts"
}

resource "aws_sns_topic_subscription" "primary_email" {
  count     = local.dns_enabled && var.alert_email != "" ? 1 : 0
  provider  = aws.primary
  topic_arn = aws_sns_topic.primary_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  count               = local.dns_enabled ? 1 : 0
  provider            = aws.primary
  alarm_name          = "${var.project}-primary-endpoint-unhealthy"
  alarm_description   = "Primary Region failed its Route 53 health check. Start the DR runbook."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  dimensions          = { HealthCheckId = aws_route53_health_check.primary[0].id }
  alarm_actions       = [aws_sns_topic.primary_alerts[0].arn]
}