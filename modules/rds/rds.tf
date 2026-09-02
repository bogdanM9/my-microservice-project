# ---------------------------------------------------------------------------
# Standard RDS instance, built when use_aurora is false.
#
# count is the whole trick. Terraform has no if statement, so a resource that
# must sometimes not exist gets a count that evaluates to 0. Everything in this
# file therefore disappears from the plan the moment use_aurora flips to true.
# ---------------------------------------------------------------------------
resource "aws_db_instance" "this" {
  count = var.use_aurora ? 0 : 1

  identifier     = var.name
  engine         = var.engine
  engine_version = local.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = var.storage_encrypted

  db_name  = var.db_name
  username = var.username
  password = local.master_password
  port     = local.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = var.publicly_accessible
  multi_az               = var.multi_az

  backup_retention_period   = var.backup_retention_period
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"
  deletion_protection       = var.deletion_protection
  apply_immediately         = var.apply_immediately

  tags = merge(var.tags, { Name = var.name })
}
