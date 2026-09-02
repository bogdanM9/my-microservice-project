# ---------------------------------------------------------------------------
# Aurora cluster, built when use_aurora is true.
#
# An Aurora cluster is two things: the cluster itself, which owns the storage,
# the endpoints and the backups, and the instances attached to it, which are
# just compute. That is why the storage and backup settings sit on the cluster
# and the instance class sits on the members.
# ---------------------------------------------------------------------------
resource "aws_rds_cluster" "this" {
  count = var.use_aurora ? 1 : 0

  cluster_identifier = "${var.name}-cluster"
  engine             = var.engine
  engine_version     = var.engine_version

  database_name   = var.db_name
  master_username = var.username
  master_password = local.master_password
  port            = local.port

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this[0].name
  storage_encrypted               = var.storage_encrypted

  backup_retention_period   = var.backup_retention_period
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"
  deletion_protection       = var.deletion_protection
  apply_immediately         = var.apply_immediately

  tags = merge(var.tags, { Name = "${var.name}-cluster" })
}

# ---------------------------------------------------------------------------
# Cluster members.
#
# One writer plus however many readers were asked for. Aurora promotes the first
# instance to writer on its own, so index 0 is the writer by convention and the
# name says so, and the rest are readers behind the reader endpoint.
# ---------------------------------------------------------------------------
resource "aws_rds_cluster_instance" "this" {
  count = var.use_aurora ? 1 + var.aurora_replica_count : 0

  identifier         = count.index == 0 ? "${var.name}-writer" : "${var.name}-reader-${count.index}"
  cluster_identifier = aws_rds_cluster.this[0].id
  instance_class     = var.instance_class

  # Taken from the cluster rather than from the variables, so a member can never
  # drift onto a different engine than the cluster it belongs to.
  engine         = aws_rds_cluster.this[0].engine
  engine_version = aws_rds_cluster.this[0].engine_version

  db_subnet_group_name    = aws_db_subnet_group.this.name
  db_parameter_group_name = aws_db_parameter_group.this.name
  publicly_accessible     = var.publicly_accessible
  apply_immediately       = var.apply_immediately

  tags = merge(var.tags, {
    Name = count.index == 0 ? "${var.name}-writer" : "${var.name}-reader-${count.index}"
    Role = count.index == 0 ? "writer" : "reader"
  })
}
