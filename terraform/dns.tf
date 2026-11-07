# Route 53 failover routing: PRIMARY ALB while healthy, otherwise the DR ALB.
locals {
  dns_enabled = var.domain_name != "" && var.hosted_zone_id != ""
}

resource "aws_route53_health_check" "primary" {
  count             = local.dns_enabled ? 1 : 0
  provider          = aws.primary
  fqdn              = module.compute_primary.alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/health" # the app returns 503 if it can't reach the DB
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "${var.project}-primary-health" }
}

resource "aws_route53_record" "primary" {
  count           = local.dns_enabled ? 1 : 0
  provider        = aws.primary
  zone_id         = var.hosted_zone_id
  name            = var.domain_name
  type            = "A"
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary[0].id

  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = module.compute_primary.alb_dns_name
    zone_id                = module.compute_primary.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  count          = local.dns_enabled ? 1 : 0
  provider       = aws.primary
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "dr"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = module.compute_dr.alb_dns_name
    zone_id                = module.compute_dr.alb_zone_id
    evaluate_target_health = false
  }
}