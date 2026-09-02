# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------
variable "name" {
  description = "Name prefix for everything the module creates: the instance or cluster identifier, the subnet group, the security group and the parameter groups. AWS identifiers are picky, so keep it lower case."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must start with a letter and contain only lower case letters, digits and hyphens."
  }
}

variable "tags" {
  description = "Extra tags added to every resource the module creates."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# The switch this whole module is built around
# ---------------------------------------------------------------------------
variable "use_aurora" {
  description = "false builds a single aws_db_instance. true builds an Aurora cluster with one writer and, if asked, some readers. The subnet group, the security group and the parameter group are built the same way either way, which is the point of the module."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------
variable "engine" {
  description = "postgres or mysql for a standard instance, aurora-postgresql or aurora-mysql for a cluster. The module reads this to pick the port, the parameter group family and the default parameters."
  type        = string
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql", "aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "engine must be postgres, mysql, aurora-postgresql or aurora-mysql."
  }
}

variable "engine_version" {
  description = "Engine version, as a prefix. \"16\" takes the newest 16.x, \"16.4\" pins that release, and null, the default, takes the newest version the engine offers. The module resolves it against the RDS API rather than trusting the string, so a version AWS has retired cannot break the apply."
  type        = string
  default     = null
}

variable "parameter_group_family" {
  description = "Overrides the parameter group family, for example postgres16 or mysql8.0. Leave it null and the module takes the family AWS reports for the resolved version."
  type        = string
  default     = null
}

variable "port" {
  description = "Port the database listens on. Leave it null and the module uses 5432 for PostgreSQL and 3306 for MySQL."
  type        = number
  default     = null
}

# ---------------------------------------------------------------------------
# Sizing
# ---------------------------------------------------------------------------
variable "instance_class" {
  description = "Instance class for the standard instance, and for every member of the Aurora cluster. db.t3.micro is the free tier eligible size for a standard instance. Aurora has no free tier and refuses anything below db.t3.medium."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Storage in GiB for the standard instance. Ignored when use_aurora is true, because Aurora grows its own storage."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper limit in GiB for storage autoscaling on the standard instance. null turns autoscaling off."
  type        = number
  default     = null
}

variable "storage_type" {
  description = "Volume type for the standard instance, gp3 or gp2 or io1."
  type        = string
  default     = "gp3"
}

variable "storage_encrypted" {
  description = "Encrypt the volume at rest with the default AWS managed key."
  type        = bool
  default     = true
}

variable "multi_az" {
  description = "Standard instance only: keep a synchronous standby in a second availability zone. Aurora already spreads its storage over three zones, so the flag does nothing there."
  type        = bool
  default     = false
}

variable "aurora_replica_count" {
  description = "Read replicas in the Aurora cluster, on top of the writer. 0 gives a cluster with one instance."
  type        = number
  default     = 0

  validation {
    condition     = var.aurora_replica_count >= 0 && var.aurora_replica_count <= 15
    error_message = "aurora_replica_count must be between 0 and 15."
  }
}

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
variable "db_name" {
  description = "Name of the database created inside the instance or cluster."
  type        = string
  default     = "appdb"
}

variable "username" {
  description = "Master user name. Some words are reserved by the engines, admin and root among them."
  type        = string
  default     = "dbadmin"
}

variable "password" {
  description = "Master password. Leave it null and the module generates one, which you read afterwards with terraform output -raw db_master_password. That keeps the password out of the repository."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC the security group belongs to."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets the database is placed in. RDS wants at least two, in different availability zones, even for a single instance."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids needs at least two subnets in different availability zones."
  }
}

variable "publicly_accessible" {
  description = "Give the database a public address. Leave it false unless you really need to reach it from outside the VPC."
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR ranges allowed to open a connection. Usually just the CIDR of the VPC."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to open a connection. Tighter than a CIDR range, because it follows the workload rather than the address."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------
variable "parameters" {
  description = "Parameters written into the DB parameter group, which applies to the instance in both modes. Leave it null and the module uses max_connections, log_statement and work_mem on PostgreSQL, or max_connections, slow_query_log and long_query_time on MySQL, since the last two PostgreSQL ones do not exist there."
  type        = map(string)
  default     = null
}

variable "cluster_parameters" {
  description = "Aurora only. Parameters written into the cluster parameter group, which holds settings that apply to the cluster as a whole. Empty by default on purpose: max_connections and work_mem are instance level in Aurora, so they belong in parameters, not here."
  type        = map(string)
  default     = {}
}

variable "parameter_apply_method" {
  description = "immediate or pending-reboot. Static parameters such as max_connections only accept pending-reboot."
  type        = string
  default     = "pending-reboot"

  validation {
    condition     = contains(["immediate", "pending-reboot"], var.parameter_apply_method)
    error_message = "parameter_apply_method must be immediate or pending-reboot."
  }
}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
variable "backup_retention_period" {
  description = "Days of automated backups kept. 0 turns backups off, which Aurora does not allow."
  type        = number
  default     = 1
}

variable "skip_final_snapshot" {
  description = "Skip the snapshot taken on delete. true for a course project, false for anything real."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Refuse to delete the database until this is turned off again."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "Apply changes at once instead of waiting for the next maintenance window. Handy while developing, disruptive in production."
  type        = bool
  default     = true
}
