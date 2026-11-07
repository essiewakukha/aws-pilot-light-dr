locals {
  tags = {
    Project   = var.project
    ManagedBy = "terraform"
  }

  use_golden_ami = var.golden_ami_id != ""
  primary_ami    = local.use_golden_ami ? var.golden_ami_id : data.aws_ssm_parameter.al2023_primary.value
  dr_ami         = local.use_golden_ami ? aws_ami_copy.golden_to_dr[0].id : data.aws_ssm_parameter.al2023_dr.value

  dr_capacity = var.dr_active ? var.primary_asg : { min = 0, max = var.primary_asg.max, desired = 0 }
}

# ---------------------------------------------------------------------------
# AMIs
# ---------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023_primary" {
  provider = aws.primary
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_ssm_parameter" "al2023_dr" {
  provider = aws.dr
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Copy the golden AMI to the DR Region (part of the "pilot light").
resource "aws_ami_copy" "golden_to_dr" {
  count             = local.use_golden_ami ? 1 : 0
  provider          = aws.dr
  name              = "${var.project}-golden-dr"
  source_ami_id     = var.golden_ami_id
  source_ami_region = var.primary_region
  encrypted         = true
}

# ---------------------------------------------------------------------------
# Networking (identical layout in both Regions)
# ---------------------------------------------------------------------------
module "network_primary" {
  source    = "./modules/network"
  providers = { aws = aws.primary }
  name      = "${var.project}-primary"
  vpc_cidr  = var.primary_vpc_cidr
}

module "network_dr" {
  source    = "./modules/network"
  providers = { aws = aws.dr }
  name      = "${var.project}-dr"
  vpc_cidr  = var.dr_vpc_cidr
}

# ---------------------------------------------------------------------------
# Compute: ALB + Auto Scaling group (identical module in both Regions)
# ---------------------------------------------------------------------------
module "compute_primary" {
  source            = "./modules/compute"
  providers         = { aws = aws.primary }
  name              = "${var.project}-primary"
  vpc_id            = module.network_primary.vpc_id
  public_subnet_ids = module.network_primary.public_subnet_ids
  ami_id            = local.primary_ami
  instance_type     = var.instance_type
  install_app       = !local.use_golden_ami
  app_source        = file("${path.module}/../app/app.py")
  db_host           = aws_db_instance.primary.address
  db_name           = var.db_name
  db_secret_arn     = aws_secretsmanager_secret.db.arn
  min_size          = var.primary_asg.min
  max_size          = var.primary_asg.max
  desired_capacity  = var.primary_asg.desired
}

module "compute_dr" {
  source            = "./modules/compute"
  providers         = { aws = aws.dr }
  name              = "${var.project}-dr"
  vpc_id            = module.network_dr.vpc_id
  public_subnet_ids = module.network_dr.public_subnet_ids
  ami_id            = local.dr_ami
  instance_type     = var.instance_type
  install_app       = !local.use_golden_ami
  app_source        = file("${path.module}/../app/app.py")
  # A promoted replica keeps its endpoint, so DR instances can be wired to it now.
  db_host = aws_db_instance.dr_replica.address
  db_name = var.db_name
  # A replica secret has the same ARN as the original, apart from the Region.
  db_secret_arn = replace(aws_secretsmanager_secret.db.arn, ":${var.primary_region}:", ":${var.dr_region}:")
  # PILOT LIGHT: 0 instances until failover
  min_size         = local.dr_capacity.min
  max_size         = local.dr_capacity.max
  desired_capacity = local.dr_capacity.desired
}