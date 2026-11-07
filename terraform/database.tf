# ---------------------------------------------------------------------------
# Credentials: one secret, replicated to the DR Region by Secrets Manager.
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  provider                = aws.primary
  name                    = "${var.project}/db-credentials"
  recovery_window_in_days = 0

  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  provider  = aws.primary
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}

# ---------------------------------------------------------------------------
# PRIMARY: RDS for PostgreSQL, Multi-AZ (handles AZ failure inside the Region)
# ---------------------------------------------------------------------------
resource "aws_security_group" "db_primary" {
  provider    = aws.primary
  name        = "${var.project}-db-primary"
  description = "PostgreSQL from app instances"
  vpc_id      = module.network_primary.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.compute_primary.instance_security_group_id]
  }
}

resource "aws_db_instance" "primary" {
  provider                = aws.primary
  identifier              = "${var.project}-primary"
  engine                  = "postgres"
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = 20
  max_allocated_storage   = 100
  storage_encrypted       = true
  db_name                 = var.db_name
  username                = var.db_username
  password                = random_password.db.result
  multi_az                = true
  db_subnet_group_name    = module.network_primary.db_subnet_group_name
  vpc_security_group_ids  = [aws_security_group.db_primary.id]
  backup_retention_period = 7 # needed before you can create read replicas
  deletion_protection     = false # set to true for real workloads
  skip_final_snapshot     = true
  apply_immediately       = true
}

# ---------------------------------------------------------------------------
# DR: cross-Region read replica = THE PILOT LIGHT
# Asynchronous replication, lag is usually seconds, well inside the 15-minute RPO.
# ---------------------------------------------------------------------------
resource "aws_kms_key" "dr_rds" {
  provider                = aws.dr
  description             = "${var.project} RDS replica encryption (DR Region)"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_security_group" "db_dr" {
  provider    = aws.dr
  name        = "${var.project}-db-dr"
  description = "PostgreSQL from DR app instances"
  vpc_id      = module.network_dr.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.compute_dr.instance_security_group_id]
  }
}

resource "aws_db_instance" "dr_replica" {
  provider               = aws.dr
  identifier             = "${var.project}-dr-replica"
  replicate_source_db    = aws_db_instance.primary.arn # cross-Region requires the ARN
  instance_class         = var.db_instance_class
  storage_encrypted      = true
  kms_key_id             = aws_kms_key.dr_rds.arn
  db_subnet_group_name   = module.network_dr.db_subnet_group_name
  vpc_security_group_ids = [aws_security_group.db_dr.id]
  multi_az               = false # cheaper while idle; enable after promotion
  skip_final_snapshot    = true
  apply_immediately      = true

  lifecycle {
    # After promotion the instance is standalone. Don't let Terraform try to
    # turn it back into a replica.
    ignore_changes = [replicate_source_db, multi_az, backup_retention_period]
  }
}