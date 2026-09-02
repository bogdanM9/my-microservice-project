# Final project: Django on AWS with Terraform, Jenkins, Argo CD and Prometheus

Munteanu Bogdan

The whole platform is built by Terraform and the application is delivered
without anyone touching the cluster. Jenkins builds the image and writes the new
tag to Git, Argo CD reads Git and deploys, Prometheus and Grafana watch what
comes out, and the application stores its data in RDS.

Components, as the brief lists them: **VPC, EKS, RDS, ECR, Jenkins, Argo CD,
Prometheus, Grafana**. Every one of them is created by `terraform apply`.

![Architecture](docs/architecture.png)

The delivery path on its own:

![CI/CD pipeline](docs/cicd-pipeline.png)

## How the pipeline works

1. I push a code change to the `final-project` branch.
2. Jenkins clones the repository into a throwaway build pod.
3. Kaniko builds the image from `django/Dockerfile` and pushes it to ECR as `v1.0.<build number>`.
4. The `git` container rewrites `image.tag` in `charts/django-app/values.yaml` and commits that back to the same branch.
5. Argo CD is watching that path in Git. It sees the new commit, notices the cluster no longer matches Git, and syncs.
6. Kubernetes rolls the Deployment and pulls the new image from ECR.

The important detail is step 4. Jenkins has no credentials for the cluster and
never runs `kubectl`. It only writes to Git. Argo CD never talks to Jenkins. The
repository is the only thing they share, and it is the single source of truth
for what runs in the cluster. That is what makes this GitOps rather than just
"a pipeline that deploys".

## What Terraform creates

| Module | What it builds |
|---|---|
| `modules/s3-backend` | S3 bucket and DynamoDB table for the remote state. Commented out on the first run, see below |
| `modules/vpc` | VPC 10.0.0.0/16, three public and three private subnets across three AZs, internet gateway, route tables |
| `modules/ecr` | ECR repository with scan on push and a lifecycle rule that keeps the last 10 images |
| `modules/eks` | EKS cluster, managed node group, IAM OIDC provider, EBS CSI driver and metrics-server addons |
| `modules/jenkins` | Namespace, storage class, IRSA role for ECR, Kaniko docker config, and the Jenkins Helm release configured through JCasC |
| `modules/argo_cd` | Argo CD Helm release, the repository credential secret, and the Argo CD `Application` |
| `modules/rds` | Universal database module. One RDS instance or a whole Aurora cluster, plus its subnet group, security group and parameter groups |
| `modules/monitoring` | kube-prometheus-stack: Prometheus, Alertmanager, Grafana, node-exporter and kube-state-metrics, in the `monitoring` namespace |

## Repository layout

```
.
├── main.tf                     wires the modules together
├── backend.tf                  remote state, commented until the bucket exists
├── variables.tf                inputs
├── outputs.tf                  URLs, commands and IDs printed after apply
├── terraform.tfvars.example    copy to terraform.tfvars and fill in
│
├── modules/
│   ├── s3-backend/             s3.tf, dynamodb.tf, variables.tf, outputs.tf
│   ├── vpc/                    vpc.tf, routes.tf, variables.tf, outputs.tf
│   ├── ecr/                    ecr.tf, variables.tf, outputs.tf
│   ├── eks/                    eks.tf, node.tf, aws_ebs_csi_driver.tf,
│   │                           metrics_server.tf, variables.tf, outputs.tf
│   ├── rds/                    shared.tf, rds.tf, aurora.tf,
│   │                           variables.tf, outputs.tf
│   ├── jenkins/                jenkins.tf, values.yaml, providers.tf,
│   │                           variables.tf, outputs.tf
│   ├── monitoring/             prometheus.tf, values.yaml, providers.tf,
│   │                           variables.tf, outputs.tf
│   └── argo_cd/                argo_cd.tf, values.yaml, providers.tf,
│       └── charts/             variables.tf, outputs.tf
│           ├── Chart.yaml      the Argo CD Application, as a small Helm chart
│           ├── values.yaml
│           └── templates/application.yaml
│
├── charts/django-app/          the application chart Argo CD deploys
│   ├── Chart.yaml
│   ├── values.yaml             image.tag on line 10 is what Jenkins rewrites
│   └── templates/              deployment, service, configmap, hpa, _helpers
│
├── django/                     the application, everything it needs to run
│   ├── Dockerfile              the image Kaniko builds
│   ├── Jenkinsfile             the pipeline
│   ├── docker-compose.yaml     the same app plus a Postgres, for local work
│   ├── manage.py, requirements.txt
│   ├── config/                 settings, urls, wsgi
│   └── core/                   views, template, static file
│
└── docs/
    ├── architecture.png        the diagram at the top
    └── cicd-pipeline.png       the delivery path on its own
```

## Prerequisites

- Terraform 1.5 or newer
- AWS CLI v2, configured with credentials that can create IAM roles, VPCs and EKS clusters
- `kubectl` and `helm`
- A GitHub Personal Access Token with the `repo` scope

The commands below are written for a POSIX shell. On Windows PowerShell every
`kubectl ... | base64 -d` becomes:

```powershell
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}')))
```

and `echo "http://$(...)"` becomes a plain `kubectl` call, since PowerShell has
no `$(...)` command substitution in double quotes.

## The four stages, in the order the brief lists them

| Stage | Command | Section |
|---|---|---|
| 1. Environment preparation | `terraform init`, then check `terraform.tfvars` | 1 |
| 2. Infrastructure deployment | `terraform apply`, then `kubectl get all -n jenkins`, `-n argocd`, `-n monitoring` | 1 |
| 3. Availability check | Jenkins and Argo CD, through their load balancers or `kubectl port-forward` | 2 and 3 |
| 4. Monitoring and metrics | Grafana, and the HPA under load | 5 |

The rest of this file is those stages in full.

## 1. How to apply Terraform

### Configure the variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars`:

```hcl
github_username = "bogdanM9"
github_token    = "ghp_..."
github_repo_url = "https://github.com/bogdanM9/my-microservice-project.git"
```

`terraform.tfvars` is in `.gitignore`. Do not commit it, it holds the token.

### Apply

```bash
terraform init
terraform plan
terraform apply
```

This takes 15 to 20 minutes, almost all of it waiting for the EKS control plane
and the node group. Terraform applies in this order because of the dependency
graph: VPC and ECR first, then EKS, then the Kubernetes and Helm providers can
authenticate, then Jenkins and Argo CD.

### Point kubectl at the cluster

```bash
aws eks update-kubeconfig --region eu-central-1 --name lesson-8-9-eks
kubectl get nodes
```

Two nodes should report `Ready`.

### Put the real ECR URL into the chart

`charts/django-app/values.yaml` ships with a placeholder account id. Replace it
with the real one, which Terraform prints:

```bash
terraform output -raw ecr_repository_url
```

Paste that value into `image.repository` in `charts/django-app/values.yaml`,
commit and push. This is a one time step. From then on Jenkins maintains the
`tag` line and nobody touches the file by hand.

### Remote backend

The state bucket cannot be described by a state that lives inside itself, so it
is created in two passes.

1. Uncomment the `module "s3_backend"` block in `main.tf` and run `terraform apply`. The bucket and the lock table are created, and the state is still local.
2. Uncomment the `terraform` block in `backend.tf` and put your account id in the bucket name.
3. Run `terraform init -migrate-state`. Terraform copies the local state into S3 and answers `yes` when it asks to confirm.

From then on the state lives in S3 and DynamoDB holds the lock.

To go back to local state, comment the backend block again and run
`terraform init -migrate-state` a second time. Do this **before**
`terraform destroy`, otherwise destroy deletes the bucket that the state it is
reading lives in, and the run fails halfway through.

## 2. How to test the Jenkins job

### Open Jenkins

```bash
kubectl -n jenkins get svc jenkins
```

Wait for `EXTERNAL-IP` to stop saying `<pending>`, which takes two or three
minutes while the load balancer is provisioned. Then:

```bash
echo "http://$(kubectl -n jenkins get svc jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

Log in as `admin`. The password:

```bash
kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d
```

### Run the pipeline

Terraform configures Jenkins through JCasC, so there is nothing to click to set
it up. Two jobs are already there:

- **seed-job** creates the pipeline job from the repository. Run it once.
- **django-app-pipeline** is the real pipeline, created by the seed job.

So:

1. Open **seed-job** and press **Build Now**. It finishes in a few seconds.
2. Go back to the dashboard. **django-app-pipeline** now exists.
3. Open it and press **Build Now**.

The build takes three to five minutes, most of it Kaniko pushing layers. Watch
the console output. The two stages that matter:

- **Build and push image to ECR** ends with the layers pushed and the tag `v1.0.1`.
- **Update image tag in Git** prints the new `values.yaml` and pushes the commit.

### Check that it worked

The image is in ECR:

```bash
aws ecr list-images --repository-name django-app --region eu-central-1
```

The commit is in GitHub: look at the history of
`charts/django-app/values.yaml`. There should be a commit by `jenkins` saying
`ci: bump django-app image tag to v1.0.1`.

### If a build fails

| Symptom | Cause |
|---|---|
| Kaniko: `denied: User is not authorized to perform ecr:PutImage` | The pod is not using `jenkins-sa`, or the IRSA annotation is missing. Check `kubectl -n jenkins get sa jenkins-sa -o yaml`. |
| Kaniko: `no basic auth credentials` | The `kaniko-docker-config` ConfigMap is not mounted, so Kaniko does not know to use the ECR credential helper. |
| Git stage: `Authentication failed` | The PAT is wrong, expired, or missing the `repo` scope. |
| Git stage: `nothing to commit` | Not a failure. The tag is already what the build produced. The pipeline skips the commit on purpose. |
| Agent pod stuck `Pending` | The two nodes are full. Either raise `desired_size` or lower the Jenkins resource requests. |
| `jenkins-0` stuck in `Init:Error`, init log says `Multiple plugin prerequisites not met` | The Jenkins core shipped by the pinned chart is older than the plugins the init container downloads. Bump `jenkins_chart_version`. This happened on the first run with chart 5.8.27, core 2.492.2, against plugins that wanted 2.504.3. |
| `helm_release.jenkins` fails with `context deadline exceeded` | The controller never became ready inside the timeout. The real reason is in the init container: `kubectl -n jenkins logs jenkins-0 -c init`. |
| Node group fails with `InvalidParameterCombination ... not eligible for Free Tier` | The account is on the AWS Free Plan. See the note on the instance type further down. |
| seed-job fails with `script not yet approved for use` | Job DSL script security is on. The JCasC block `job-dsl-security` in `modules/jenkins/values.yaml` turns it off. |
| Pipeline fails to compile with `Invalid option type "timestamps"` | The `timestamper` plugin is missing from `installPlugins`. Every option used in the Jenkinsfile needs its plugin listed there. |

## 3. How to view the result in Argo CD

### Open Argo CD

```bash
echo "http://$(kubectl -n argocd get svc argo-cd-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

Log in as `admin`. The password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### What you should see

One Application, `django-app`. Click it and you get the resource tree:
Deployment, ReplicaSet, the pods, the Service, the ConfigMap and the HPA, each
with its own health icon.

Two labels matter:

- **Sync status: Synced** means the cluster matches Git.
- **Health: Healthy** means the pods are actually running and passing their probes.

Straight after a Jenkins build it will briefly say **OutOfSync**, because Git has
a new tag and the cluster is still on the old one. Automated sync is enabled, so
it fixes itself. To not wait for the poll interval, press **Refresh**, or
**Sync** to force it immediately.

### Prove it end to end

```bash
# the app URL
echo "http://$(kubectl get svc django-app-django-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

The home page shows the image version and the pod name. Now:

1. Change something visible, for example a line in `core/templates/core/home.html`.
2. Commit and push to `final-project`.
3. Run **django-app-pipeline** in Jenkins.
4. Watch Argo CD go OutOfSync, then Synced.
5. Reload the page. The version number went up and the pod name changed.

Nobody ran `kubectl apply` anywhere in that loop.

### Useful commands

```bash
# is the tag in the cluster the same as the tag in Git?
kubectl get deploy django-app-django-app -o jsonpath='{.spec.template.spec.containers[0].image}'

# pods, service, hpa
kubectl get pods,svc,hpa

# is the HPA actually reading metrics, or does it show <unknown>?
kubectl get hpa django-app-django-app

# what did Argo CD do and when
kubectl -n argocd get applications django-app -o yaml | grep -A 10 "operationState"
```

## 4. The universal `rds` module

`modules/rds` builds either a single RDS instance or a whole Aurora cluster from
the same call. One boolean decides which, and nothing around it changes.

### Usage

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

### What it builds

| `use_aurora` | Resources |
|---|---|
| `false` | `aws_db_instance`, one instance |
| `true` | `aws_rds_cluster`, plus `aws_rds_cluster_instance` for the writer and for each reader |
| both | `aws_db_subnet_group`, `aws_security_group` with its rules, `aws_db_parameter_group` |
| `true` only | `aws_rds_cluster_parameter_group` |

Terraform has no `if`, so the switch is `count = var.use_aurora ? 1 : 0` on the
Aurora resources and the reverse on the standard instance. The branch that is
not taken evaluates to zero resources and disappears from the plan.

### Variables

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

### Outputs

`endpoint`, `reader_endpoint`, `port`, `database_name`, `master_username`,
`master_password` (sensitive), `identifier`, `instance_identifiers`, `is_aurora`,
`security_group_id`, `subnet_group_name`, `parameter_group_name`,
`cluster_parameter_group_name`.

The names are the same in both modes, so whatever consumes the module never has
to know which kind of database it got. `endpoint` is the cluster writer endpoint
for Aurora and the instance address otherwise. The Aurora only outputs return
`null` for a standard instance.

### The parameters, and why they are where they are

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

### How to change the database

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

### A note on the names

`git_branch` defaults to `final-project`, so Jenkins builds from this branch and
Argo CD watches it.

`project_name` and `cluster_name` still say `lesson-8-9`. The cluster, the VPC
and the ECR repository were built during that task and renaming them would tear
the entire environment down and build it again, for nothing but a nicer string.

## 5. Monitoring: Prometheus and Grafana

`modules/monitoring` installs kube-prometheus-stack into the `monitoring`
namespace. One chart, because installing Prometheus and Grafana separately means
wiring the scrape configuration and the Grafana data source by hand, and the
chart already does both.

What it brings, and what each part is for:

| Component | What it gives |
|---|---|
| Prometheus | The time series database. 20 GiB on a gp3 volume, 7 days of retention |
| Prometheus operator | Turns `ServiceMonitor` and `PodMonitor` objects into scrape configuration |
| node-exporter | CPU, memory, disk and network for every node, as a DaemonSet |
| kube-state-metrics | The state of Kubernetes objects: deployment replicas, pod restarts, and the HPA current and desired replica counts |
| Grafana | The dashboards. The chart ships the cluster, node, namespace and pod ones and points them at Prometheus already |
| Alertmanager | Where the alerting rules that ship with the chart send their alerts. No receiver is configured, wiring it to Slack is a different exercise |

The selectors are deliberately opened up:

```yaml
serviceMonitorSelectorNilUsesHelmValues: false
podMonitorSelectorNilUsesHelmValues: false
```

Without those two lines the operator only picks up monitors that carry the
release label, so anything created outside this chart is silently ignored and
the target list looks fine while missing half the cluster.

`kubeControllerManager`, `kubeScheduler`, `kubeEtcd` and `kubeProxy` are turned
off. EKS runs the control plane and does not expose them, so leaving them on
gives four targets that sit red forever and make the target page useless.

### Open Grafana

```bash
kubectl -n monitoring get svc kube-prometheus-stack-grafana
```

Wait for `EXTERNAL-IP`, then open it in a browser. User `admin`, and the
password:

```bash
terraform output -raw grafana_admin_password
```

The brief asks for a port-forward instead, which works the same and does not go
through the load balancer:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

Prometheus has no load balancer on purpose. Its UI is reachable the same way:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

### What to look at

In Grafana, **Dashboards**, then:

- **Kubernetes / Compute Resources / Cluster** for the whole cluster
- **Kubernetes / Compute Resources / Namespace (Workloads)**, namespace
  `default`, for the application
- **Node Exporter / Nodes** for the machines themselves

To see the autoscaling, put some load on the application and watch the pod count
climb from 2 towards 6:

```bash
kubectl get hpa -w
```

In Prometheus, these two queries show the same thing in numbers:

```promql
kube_horizontalpodautoscaler_status_current_replicas{horizontalpodautoscaler="django-app-django-app"}
kube_horizontalpodautoscaler_spec_target_metric{horizontalpodautoscaler="django-app-django-app"}
```

## 6. How the application reaches the database

Nothing about the database is committed. The chain is:

1. `modules/rds` builds the instance and generates the master password.
2. The root `main.tf` writes a Kubernetes Secret named `django-db` in the
   application namespace, filled from the module outputs: host, port, database
   name, user, password.
3. `charts/django-app/values.yaml` names that Secret, and the Deployment reads
   it with `envFrom`, so the values arrive as environment variables.
4. `django/config/settings.py` reads `POSTGRES_HOST` and the rest. When the
   variable is missing, which is the case for a plain `docker run` or a test, it
   falls back to a local SQLite file and still starts.

The Helm chart therefore never contains a host name or a password, and neither
does the repository. Terraform is the only thing that knows both halves.

To check it from outside, the home page shows the database line, and there is an
endpoint that answers in JSON:

```bash
curl "http://$(kubectl get svc django-app-django-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/dbz/"
```

```json
{"engine": "postgresql", "host": "lesson-8-9-db.xxxx.eu-central-1.rds.amazonaws.com", "ok": true, "detail": "connected"}
```

It returns 503 instead of 200 when the query fails, so it can be curled from a
script. The probes deliberately do not use it: a probe that touches the database
turns a slow query into a restart loop.

## Design decisions worth explaining

**Kaniko instead of Docker in Docker.** Building an image inside Kubernetes with
the Docker daemon means mounting the host socket or running a privileged
container, both of which give the build a way out of its own container. Kaniko
builds the layers in userspace and needs no daemon and no privileges.

**IRSA instead of an access key.** The Kaniko pod needs to push to ECR. The
obvious way is to put an AWS access key in a Jenkins credential. Instead, the
service account carries an `eks.amazonaws.com/role-arn` annotation, EKS injects
a short lived web identity token into the pod, and the AWS SDK exchanges it for
temporary credentials. No long lived key exists anywhere, so there is nothing to
leak or rotate. The role is also scoped to this one ECR repository, apart from
`ecr:GetAuthorizationToken`, which AWS does not allow to be scoped.

**JCasC instead of clicking through the setup wizard.** The Jenkins
configuration, including the GitHub credential and the seed job, is written by
Terraform into `modules/jenkins/values.yaml`. If the Jenkins pod is deleted, it
comes back configured. Nothing about this setup depends on somebody remembering
what they clicked.

**A separate `/healthz/` endpoint.** The probes hit an endpoint that returns 200
and nothing else. Pointing a liveness probe at a page that queries a database
turns a slow query into a restart loop, and a restart loop into an outage.

**No NAT gateway.** The nodes are in public subnets. A NAT gateway costs about
$33 a month, and the only thing in the private subnets is RDS, which has no
reason to reach the internet: the pods connect to it from inside the VPC and
nothing goes the other way. Moving the node group into the private subnets later
is a one line change, but a NAT gateway has to be added at the same time or the
nodes never become Ready.

**The database is not reachable from the internet.** It sits in the private
subnets, its security group allows port 5432 from the VPC CIDR and from nothing
else, and it is encrypted at rest. The password is generated by Terraform and
handed to the pods through a Kubernetes Secret, so it is in the state file and in
the cluster, and nowhere else.

**The gp3 storage class is created by the Jenkins module.** It is cluster wide
and not specific to Jenkins, so on paper it belongs to the EKS module. It cannot
live there: the Kubernetes provider is configured from the EKS cluster data
source, so a Kubernetes resource inside that module would need the provider
before the module it depends on has finished, which is a dependency cycle. It
sits in the first module that needed a volume, and the monitoring module takes
the name from that module's output rather than hardcoding the string, so
Terraform knows the order.

## Cost

The cluster is not free. Roughly, per day:

| Item | Cost |
|---|---|
| EKS control plane | $2.40 |
| 2 x m7i-flex.large nodes | $4.30 |
| 3 load balancers (Jenkins, Argo CD, the app) | $1.30 |
| EBS volumes, ECR storage, data transfer | small change |
| RDS db.t3.micro, single AZ | free tier for the first 750 hours a month |
| Prometheus and Grafana volumes, 25 GiB | about $0.10 |
| 4th load balancer, for Grafana | $0.45 |

Around **$9 a day**, so do not leave it running.

Turning on Aurora changes that. A `db.t3.medium` writer is about 0.08 USD an
hour, roughly 2 USD a day, and each reader costs the same again.

### A note on the instance type

This account is on the AWS Free Plan. That plan refuses to launch any instance
type that is not free tier eligible, and the first apply failed on exactly that:

```
AsgInstanceLaunchFailures: Could not launch On-Demand Instances.
InvalidParameterCombination - The specified instance type is not eligible for Free Tier.
```

The types the account does allow:

```bash
aws ec2 describe-instance-types \
  --filters "Name=free-tier-eligible,Values=true" \
  --query "sort(InstanceTypes[].InstanceType)" \
  --region eu-central-1 --output table
```

which returns `t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, `c7i-flex.large`
and `m7i-flex.large`.

The micro types cannot run this project. 1 GiB of RAM is less than the Jenkins
controller alone requests, and more importantly the VPC CNI allows only **4 pods
per node** on a micro instance, against the roughly 15 that CoreDNS,
metrics-server, the EBS CSI controller, Jenkins, Argo CD and the application add
up to. No number of micro nodes fixes the RAM problem.

`m7i-flex.large` gives 8 GiB and about 29 pods per node, so two nodes are
comfortable.

## Destroy everything

```bash
# Delete the Argo CD Application first. It has a finalizer that cleans up what
# it deployed, including the app load balancer. Skipping this leaves an orphaned
# load balancer behind that Terraform does not know about and will not delete.
kubectl -n argocd delete application django-app

# Wait for the app load balancer to disappear
kubectl get svc

terraform destroy
```

`terraform destroy` takes care of the other three load balancers, the Jenkins
one, the Argo CD one and the Grafana one, because those services are part of
Helm releases that Terraform owns. The application load balancer is the only one
it does not know about, which is why the Argo CD Application goes first.

The RDS instance is deleted with `skip_final_snapshot = true`, so nothing is
kept. Set that variable to `false` first if the data matters.

If `destroy` hangs on the VPC, it is almost always a load balancer or an ENI
that Kubernetes created and Terraform does not track. Check the EC2 console
under Load Balancers and Network Interfaces, delete what is left, and run
`terraform destroy` again.

If you moved the state into S3, move it back to local **before** destroying, as
described in the remote backend section.
