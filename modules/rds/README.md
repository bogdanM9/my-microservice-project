# `rds`

A universal database module: one RDS instance or a whole Aurora cluster from the
same call, decided by `use_aurora`.

`modules/rds` builds either a single RDS instance or a whole Aurora cluster from
the same call. One boolean decides which, and nothing around it changes.

## Usage

```hcl
module "rds" {
  source = "./modules/rds"

  name       = "lesson-8-9-db"
  use_aurora = false          # true gives an Aurora cluster instead

  engine         = "postgres"
  engine_version = "16.6"
  instance_class = "db.t3.micro"
  multi_az       = false

  db_name  = "appdb"
  username = "dbadmin"
  # password is left out on purpose, see below

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  allowed_cidr_blocks = [module.vpc.vpc_cidr_block]

  tags = { Component = "database" }
}
```

That is exactly how `main.tf` calls it, except that the values come from root
variables so the whole database can be changed from `terraform.tfvars` without
touching any `.tf` file.

The password is not in the code and not in `terraform.tfvars`. When `password`
is left null the module generates one and keeps it in state. Read it after the
apply:

```bash
terraform output -raw db_master_password
```

## What it builds

| `use_aurora` | Resources |
|---|---|
| `false` | `aws_db_instance`, one instance |
| `true` | `aws_rds_cluster`, plus `aws_rds_cluster_instance` for the writer and for each reader |
| both | `aws_db_subnet_group`, `aws_security_group` with its rules, `aws_db_parameter_group` |
| `true` only | `aws_rds_cluster_parameter_group` |

Terraform has no `if`, so the switch is `count = var.use_aurora ? 1 : 0` on the
Aurora resources and the reverse on the standard instance. The branch that is
not taken evaluates to zero resources and disappears from the plan.

## Variables

Identity and the switch:

| Variable | Type | Default | What it does |
|---|---|---|---|
| `name` | string | required | Prefix for every resource. Validated: lower case letters, digits and hyphens, starting with a letter |
| `use_aurora` | bool | `false` | `false` builds one `aws_db_instance`, `true` builds an Aurora cluster |
| `tags` | map(string) | `{}` | Added to everything the module creates |

Engine:

| Variable | Type | Default | What it does |
|---|---|---|---|
| `engine` | string | `postgres` | `postgres`, `mysql`, `aurora-postgresql` or `aurora-mysql`. Validated |
| `engine_version` | string | `16.6` | Change it together with `engine` |
| `parameter_group_family` | string | `null` | Overrides the derived family. `null` means derive it |
| `port` | number | `null` | `null` means 5432 for PostgreSQL, 3306 for MySQL |

Sizing:

| Variable | Type | Default | What it does |
|---|---|---|---|
| `instance_class` | string | `db.t3.micro` | Used by the instance and by every Aurora member |
| `allocated_storage` | number | `20` | GiB. Ignored by Aurora, which manages its own storage |
| `max_allocated_storage` | number | `null` | Upper limit for storage autoscaling. `null` turns it off |
| `storage_type` | string | `gp3` | Standard instance only |
| `storage_encrypted` | bool | `true` | Encryption at rest with the AWS managed key |
| `multi_az` | bool | `false` | Standard instance only. Aurora already spans three zones |
| `aurora_replica_count` | number | `0` | Readers on top of the writer. Validated, 0 to 15 |

Credentials:

| Variable | Type | Default | What it does |
|---|---|---|---|
| `db_name` | string | `appdb` | Database created inside the instance or cluster |
| `username` | string | `dbadmin` | Master user. `admin` and `root` are reserved by the engines |
| `password` | string, sensitive | `null` | `null` generates one, readable through the output |

Network:

| Variable | Type | Default | What it does |
|---|---|---|---|
| `vpc_id` | string | required | VPC the security group is created in |
| `subnet_ids` | list(string) | required | At least two, in different zones. Validated |
| `publicly_accessible` | bool | `false` | Give the database a public address |
| `allowed_cidr_blocks` | list(string) | `[]` | Ranges allowed to connect. One ingress rule each |
| `allowed_security_group_ids` | list(string) | `[]` | Source security groups allowed to connect |

Parameters:

| Variable | Type | Default | What it does |
|---|---|---|---|
| `parameters` | map(string) | `null` | Instance level parameters. `null` picks the defaults below |
| `cluster_parameters` | map(string) | `{}` | Aurora only, cluster level parameters |
| `parameter_apply_method` | string | `pending-reboot` | Static parameters accept nothing else |

Lifecycle:

| Variable | Type | Default | What it does |
|---|---|---|---|
| `backup_retention_period` | number | `1` | Days of automated backups |
| `skip_final_snapshot` | bool | `true` | Fine for a course project, wrong for production |
| `deletion_protection` | bool | `false` | Refuse to delete until turned off |
| `apply_immediately` | bool | `true` | Do not wait for the maintenance window |

## Outputs

`endpoint`, `reader_endpoint`, `port`, `database_name`, `master_username`,
`master_password` (sensitive), `identifier`, `instance_identifiers`, `is_aurora`,
`security_group_id`, `subnet_group_name`, `parameter_group_name`,
`cluster_parameter_group_name`.

The names are the same in both modes, so whatever consumes the module never has
to know which kind of database it got. `endpoint` is the cluster writer endpoint
for Aurora and the instance address otherwise. The Aurora only outputs return
`null` for a standard instance.

## The parameters, and why they are where they are

The parameter group gets `max_connections`, `log_statement` and `work_mem` on
PostgreSQL. On MySQL it gets `max_connections`, `slow_query_log` and
`long_query_time` instead, because `log_statement` and `work_mem` are PostgreSQL
settings and MySQL rejects them outright.

The family is derived rather than asked for. PostgreSQL families carry only the
major version, so `16.6` becomes `postgres16`. MySQL families carry major and
minor, so `8.0.39` becomes `mysql8.0`. Aurora MySQL version strings look like
`8.0.mysql_aurora.3.08.2`, and taking the first two parts of that still gives
`8.0`.

The three parameters go into a **DB** parameter group even in Aurora mode, and
that is on purpose. `max_connections` and `work_mem` are instance level settings
in Aurora, so a cluster parameter group would refuse them. The cluster parameter
group is still created for Aurora, and `cluster_parameters` is where genuinely
cluster wide settings belong.

## How to change the database

Everything below is a change in `terraform.tfvars` only.

Aurora instead of a single instance:

```hcl
use_aurora           = true
db_engine            = "aurora-postgresql"
db_engine_version    = "16.6"
db_instance_class    = "db.t3.medium"   # Aurora refuses anything smaller
aurora_replica_count = 1                # writer plus one reader
```

MySQL instead of PostgreSQL:

```hcl
db_engine         = "mysql"
db_engine_version = "8.0.39"
```

A bigger instance, and a standby in a second zone:

```hcl
db_instance_class = "db.t3.small"
db_multi_az       = true
```

Reachable from outside the VPC, for example from your own laptop while
developing. This moves the database into the public subnets and gives it a
public address, so the allowed range is not defaulted to the whole internet:

```hcl
db_publicly_accessible = true
db_public_cidr_blocks  = ["203.0.113.7/32"]   # your address, not 0.0.0.0/0
```

Then:

```bash
terraform plan
terraform apply
```

Two things to know before flipping `use_aurora` on a database that already
exists. Terraform will destroy one and create the other, because they are
different resources, so the data does not come along. And Aurora is not free
tier eligible: a `db.t3.medium` writer is roughly 0.08 USD an hour, while the
`db.t3.micro` standard instance is covered by the free tier for the first 750
hours a month.
