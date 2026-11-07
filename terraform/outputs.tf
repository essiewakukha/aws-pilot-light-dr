output "primary_alb_url" {
  value = "http://${module.compute_primary.alb_dns_name}"
}

output "dr_alb_url" {
  value = "http://${module.compute_dr.alb_dns_name}"
}

output "app_url" {
  value = local.dns_enabled ? "http://${var.domain_name}" : "(no domain configured, use primary_alb_url)"
}

output "primary_db_identifier" {
  value = aws_db_instance.primary.identifier
}

output "dr_replica_identifier" {
  value = aws_db_instance.dr_replica.identifier
}

output "dr_asg_name" {
  value = module.compute_dr.asg_name
}

output "dr_target_group_arn" {
  value = module.compute_dr.target_group_arn
}

# Paste-ready environment for scripts/*.sh
output "script_env" {
  value = <<-EOT
    export PRIMARY_REGION=${var.primary_region}
    export DR_REGION=${var.dr_region}
    export DR_REPLICA_ID=${aws_db_instance.dr_replica.identifier}
    export DR_ASG_NAME=${module.compute_dr.asg_name}
    export DR_TG_ARN=${module.compute_dr.target_group_arn}
    export DR_ALB_DNS=${module.compute_dr.alb_dns_name}
    export DR_DESIRED=${var.primary_asg.desired}
  EOT
}