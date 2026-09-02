# ---------------------------------------------------------------------------
# Everything in this file is built in both modes, standard instance and Aurora.
# That is what makes the module universal: the caller flips use_aurora and the
# surrounding plumbing does not change.
# ---------------------------------------------------------------------------

locals {
  # aurora-postgresql and postgres both match, which is exactly what we want.
  is_postgres = can(regex("postgres", var.engine))

  version_parts = split(".", var.engine_version)

  # PostgreSQL parameter group families carry only the major version, so 16.6
  # becomes postgres16. MySQL families carry major and minor, so 8.0.39 becomes
  # mysql8.0. Aurora MySQL version strings look like 8.0.mysql_aurora.3.08.2,
  # and taking the first two parts of that still gives 8.0.
  family_version = local.is_postgres ? local.version_parts[0] : join(".", slice(local.version_parts, 0, min(2, length(local.version_parts))))

  parameter_group_family = coalesce(var.parameter_group_family, "${var.engine}${local.family_version}")

  port = coalesce(var.port, local.is_postgres ? 5432 : 3306)

  # Basic parameters, picked to match the engine. log_statement and work_mem are
  # PostgreSQL settings and MySQL rejects them, so MySQL gets the two closest
  # equivalents instead.
  default_parameters = local.is_postgres ? {
    max_connections = "100"
    log_statement   = "ddl"
    work_mem        = "4096"
    } : {
    max_connections = "100"
    slow_query_log  = "1"
    long_query_time = "2"
  }

  parameters = var.parameters != null ? var.parameters : local.default_parameters

  master_password = var.password != null ? var.password : random_password.master[0].result
}

# ---------------------------------------------------------------------------
# Master password
#
# Generated here when the caller does not supply one, so that no password has to
# be written into terraform.tfvars or committed. Read it afterwards with
# terraform output -raw db_master_password.
#
# special is off because RDS rejects a handful of punctuation characters in a
# master password, and excluding all of them is simpler than listing them.
# ---------------------------------------------------------------------------
resource "random_password" "master" {
  count = var.password == null ? 1 : 0

  length  = 24
  special = false
}

# ---------------------------------------------------------------------------
# Subnet group
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-subnet-group"
  description = "Subnets ${var.name} is placed in"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-subnet-group" })
}

# ---------------------------------------------------------------------------
# Security group
#
# The rules are separate resources rather than inline blocks. Inline blocks
# describe the whole rule set at once, so two callers touching the same group
# fight each other. Separate rules also let the caller pass any number of CIDRs
# and source security groups without the module guessing.
# ---------------------------------------------------------------------------
resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Database access for ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "Database traffic from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
}

resource "aws_vpc_security_group_ingress_rule" "from_security_group" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "Database traffic from ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Outbound, needed for things like the engine reaching KMS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# Parameter groups
#
# The DB parameter group is created in both modes. In standard mode it is
# attached to the instance, in Aurora mode to every member of the cluster. That
# is deliberate: max_connections and work_mem are instance level settings even
# in Aurora, so a cluster parameter group would refuse them.
#
# The cluster parameter group is created only for Aurora, and holds whatever the
# caller puts in cluster_parameters, which is the right place for settings that
# apply to the cluster as a whole.
# ---------------------------------------------------------------------------
resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-params"
  family      = local.parameter_group_family
  description = "Instance level parameters for ${var.name}"

  dynamic "parameter" {
    for_each = local.parameters

    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = var.parameter_apply_method
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-params" })
}

resource "aws_rds_cluster_parameter_group" "this" {
  count = var.use_aurora ? 1 : 0

  name        = "${var.name}-cluster-params"
  family      = local.parameter_group_family
  description = "Cluster level parameters for ${var.name}"

  dynamic "parameter" {
    for_each = var.cluster_parameters

    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = var.parameter_apply_method
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-cluster-params" })
}
