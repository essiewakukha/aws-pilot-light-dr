variable "project" {
  description = "Name prefix for all resources."
  type        = string
  default     = "pilot-light-dr"
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"
}

variable "primary_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "dr_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_engine_version" {
  type    = string
  default = "16.4"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "primary_asg" {
  description = "Capacity of the primary Auto Scaling group."
  type = object({
    min     = number
    max     = number
    desired = number
  })
  default = { min = 2, max = 6, desired = 2 }
}

variable "dr_active" {
  description = <<-EOT
    false = pilot light (DR ASG at 0 instances: only the DB replica runs).
    true  = DR is serving traffic (ASG scaled to match production).
    The failover script scales the ASG directly for speed. Set this to true
    afterwards so Terraform doesn't scale it back to 0.
  EOT
  type        = bool
  default     = false
}

variable "golden_ami_id" {
  description = <<-EOT
    Optional: a pre-baked AMI in the primary Region. If set, it is copied to the
    DR Region (aws_ami_copy) and used in both Regions. If empty, the latest
    Amazon Linux 2023 AMI is used and the app is installed at boot via user data.
  EOT
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "FQDN users hit, e.g. app.example.com. Leave empty to skip Route 53."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 public hosted zone ID for domain_name."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email that receives RPO-breach and health-check alarms (optional)."
  type        = string
  default     = ""
}

variable "rpo_seconds" {
  description = "RPO target. An alarm fires when the replica lag gets close to it."
  type        = number
  default     = 900
}