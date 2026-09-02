# Final project: Django on AWS with Terraform, Jenkins, Argo CD and Prometheus

Munteanu Bogdan

The whole platform is built by Terraform and the application is delivered
without anyone touching the cluster. Jenkins builds the image and writes the new
tag to Git, Argo CD reads Git and deploys, Prometheus and Grafana watch what
comes out, and the application stores its data in RDS.

![Architecture](docs/architecture.png)

| Component | Where it is built | What it does here |
|---|---|---|
| VPC | `modules/vpc` | 10.0.0.0/16, three public and three private subnets across three AZs |
| EKS | `modules/eks` | Cluster, managed node group, IAM OIDC provider, EBS CSI driver and metrics-server |
| RDS | `modules/rds` | PostgreSQL instance, or an Aurora cluster, from the same module |
| ECR | `modules/ecr` | Private registry the pipeline pushes to |
| Jenkins | `modules/jenkins` | CI, configured entirely through JCasC |
| Argo CD | `modules/argo_cd` | CD, one Application with automated sync |
| Prometheus, Grafana | `modules/monitoring` | kube-prometheus-stack in the `monitoring` namespace |

## How the delivery path works

![CI/CD pipeline](docs/cicd-pipeline.png)

1. I push a code change to the `final-project` branch.
2. Jenkins clones the repository into a throwaway build pod.
3. Kaniko builds the image from `django/Dockerfile` and pushes it to ECR as `v1.0.<build number>`.
4. The `git` container rewrites `image.tag` in `charts/django-app/values.yaml` and commits that back to the same branch.
5. Argo CD sees the new commit, notices the cluster no longer matches Git, and syncs.
6. Kubernetes rolls the Deployment and pulls the new image from ECR.

Step 4 is the important one. Jenkins has no credentials for the cluster and
never runs `kubectl`. It only writes to Git. Argo CD never talks to Jenkins. The
repository is the only thing they share, and it is the single source of truth for
what runs in the cluster. That is what makes this GitOps rather than just a
pipeline that deploys.

## Repository layout

```
.
├── main.tf, variables.tf, outputs.tf    wires the modules together
├── backend.tf                           remote state, commented until the bucket exists
├── terraform.tfvars.example             copy to terraform.tfvars and fill in
│
├── modules/
│   ├── s3-backend/     s3.tf, dynamodb.tf, variables.tf, outputs.tf
│   ├── vpc/            vpc.tf, routes.tf, variables.tf, outputs.tf
│   ├── ecr/            ecr.tf, variables.tf, outputs.tf
│   ├── eks/            eks.tf, node.tf, aws_ebs_csi_driver.tf, metrics_server.tf,
│   │                   variables.tf, outputs.tf
│   ├── rds/            shared.tf, rds.tf, aurora.tf, variables.tf, outputs.tf
│   ├── jenkins/        jenkins.tf, values.yaml, providers.tf, variables.tf, outputs.tf
│   ├── monitoring/     prometheus.tf, values.yaml, providers.tf, variables.tf, outputs.tf
│   └── argo_cd/        argo_cd.tf, values.yaml, providers.tf, variables.tf, outputs.tf
│       └── charts/     the Argo CD Application, as a small Helm chart
│
├── charts/django-app/  the application chart Argo CD deploys
│   ├── values.yaml     image.tag is the line Jenkins rewrites
│   └── templates/      deployment, service, configmap, hpa, _helpers
│
├── django/             the application
│   ├── Dockerfile, Jenkinsfile, docker-compose.yaml
│   ├── manage.py, requirements.txt
│   ├── config/         settings, urls, wsgi
│   └── core/           views, template, static file
│
└── docs/               architecture.png, cicd-pipeline.png
```

## Prerequisites

- Terraform 1.5 or newer
- AWS CLI v2, with credentials that can create IAM roles, VPCs and EKS clusters
- `kubectl` and `helm`
- A GitHub Personal Access Token with the `repo` scope

The commands below are written for a POSIX shell. On Windows PowerShell,
`kubectl ... | base64 -d` becomes:

```powershell
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}')))
```

## The four stages

| Stage | What to run | Section |
|---|---|---|
| 1. Environment preparation | `terraform init`, check `terraform.tfvars` | 1 |
| 2. Infrastructure deployment | `terraform apply`, then `kubectl get all` in the three namespaces | 1 |
| 3. Availability check | Jenkins and Argo CD | 2 and 3 |
| 4. Monitoring and metrics | Grafana, and the HPA under load | 4 |

## 1. Apply Terraform

```bash
cp terraform.tfvars.example terraform.tfvars
```

Fill in the three values that have no default:

```hcl
github_username = "bogdanM9"
github_token    = "ghp_..."
github_repo_url = "https://github.com/bogdanM9/my-microservice-project.git"
```

`terraform.tfvars` is in `.gitignore`. Do not commit it, it holds the token.

```bash
terraform init
terraform plan
terraform apply
```

This takes 20 to 25 minutes, almost all of it waiting for the EKS control plane
and the node group. Terraform works the order out from the dependency graph: VPC
and ECR first, then EKS, then the Kubernetes and Helm providers can
authenticate, then RDS, Jenkins, Argo CD and the monitoring stack.

Then point `kubectl` at the cluster and check the three namespaces:

```bash
aws eks update-kubeconfig --region eu-central-1 --name lesson-8-9-eks

kubectl get nodes
kubectl get all -n jenkins
kubectl get all -n argocd
kubectl get all -n monitoring
```

One step is manual and happens once. `charts/django-app/values.yaml` ships with
a placeholder account id in `image.repository`. Replace it with the real one,
which `terraform output -raw ecr_repository_url` prints, then commit and push.
From then on Jenkins maintains the `tag` line and nobody edits the file by hand.

### Remote backend

The state bucket cannot be described by a state that lives inside itself, so it
is created in two passes: uncomment `module "s3_backend"` in `main.tf` and
apply, then uncomment the `terraform` block in `backend.tf` and run
`terraform init -migrate-state`. To go back to local state, comment the backend
block and migrate a second time. Do that **before** `terraform destroy`,
otherwise destroy deletes the bucket holding the state it is reading from.

## 2. Test the Jenkins job

```bash
kubectl -n jenkins get svc jenkins
kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d
```

Wait for `EXTERNAL-IP`, open it, log in as `admin`.

Terraform configures Jenkins through JCasC, so there is nothing to set up by
hand. Two jobs are already there: **seed-job**, which creates the pipeline job
from the repository and is run once, and **django-app-pipeline**, the real
pipeline that the seed job creates.

Press **Build Now** on `seed-job`, go back to the dashboard, then press
**Build Now** on `django-app-pipeline`. The build takes three to five minutes,
most of it Kaniko pushing layers. The two stages that matter are **Build and
push image to ECR** and **Update image tag in Git**.

Check it landed with `aws ecr list-images --repository-name django-app --region
eu-central-1`, and look at the history of `charts/django-app/values.yaml` on
GitHub: there should be a commit by `jenkins` saying `ci: bump django-app image
tag to v1.0.x`.

### When a build fails

Everything in this table actually happened while building this project.

| Symptom | Cause |
|---|---|
| Kaniko: `denied: not authorized to perform ecr:PutImage` | The pod is not using `jenkins-sa`, or the IRSA annotation is missing |
| Kaniko: `no basic auth credentials` | The `kaniko-docker-config` ConfigMap is not mounted, so Kaniko does not use the ECR credential helper |
| Git stage: `Authentication failed` | The PAT is wrong, expired, or missing the `repo` scope. A public repo clones fine without it, so only the push fails |
| Git stage: `nothing to commit` | Not a failure. The tag is already what the build produced, and the pipeline skips the commit on purpose |
| Agent pod stuck `Pending` | The nodes are full. Raise `desired_size` or lower the Jenkins requests |
| `jenkins-0` in `Init:Error`, log says `plugin prerequisites not met` | The Jenkins core in the pinned chart is older than the plugins it downloads. Bump `jenkins_chart_version` |
| seed-job: `script not yet approved for use` | Job DSL script security. The `job-dsl-security` block in `modules/jenkins/values.yaml` turns it off |
| Pipeline: `Invalid option type "timestamps"` | The `timestamper` plugin is missing from `installPlugins` |
| Node group: `not eligible for Free Tier` | See the note on the instance type below |

## 3. View the result in Argo CD

```bash
kubectl -n argocd get svc argo-cd-argocd-server
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Log in as `admin`. There is one Application, `django-app`. Open it and the
resource tree appears: Deployment, ReplicaSet, pods, Service, ConfigMap and HPA,
each with its own health icon.

Two labels matter. **Synced** means the cluster matches Git, **Healthy** means
the pods are running and passing their probes. Straight after a Jenkins build it
briefly says **OutOfSync**, because Git has a new tag and the cluster is still on
the old one. Automated sync fixes it within about three minutes, or immediately
if you press **Refresh**.

The **Last Sync** panel is the proof the loop is closed: the author is `jenkins`
and the message is the tag bump commit, not anything a person typed.

### Prove it end to end

```bash
echo "http://$(kubectl get svc django-app-django-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

The home page shows the image version, the pod name and the database status.
Change a line in `django/core/templates/core/home.html`, push, run the pipeline,
and watch Argo CD go OutOfSync and back: the version goes up and the pod name
changes, with nobody running `kubectl apply` anywhere in that loop.

## 4. Monitoring and metrics

`modules/monitoring` installs kube-prometheus-stack, one chart that brings the
operator, Prometheus with a 20 GiB volume and 7 days of retention, Grafana with
the dashboards it ships, Alertmanager, node-exporter on every node and
kube-state-metrics. Installing them separately would mean wiring the scrape
configuration and the Grafana data source by hand.

```bash
kubectl -n monitoring get svc kube-prometheus-stack-grafana
terraform output -raw grafana_admin_password
```

Or, without going through the load balancer:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

In Grafana, **Dashboards**, then *Kubernetes / Compute Resources / Cluster* for
the whole cluster, *Namespace (Workloads)* with namespace `default` for the
application, and *Node Exporter / Nodes* for the machines.

The autoscaling shows up there too, because kube-state-metrics exports the HPA
numbers. Put load on the application and watch `kubectl get hpa -w`, or query
Prometheus directly:

```promql
kube_horizontalpodautoscaler_status_current_replicas{horizontalpodautoscaler="django-app-django-app"}
```

Two details in `modules/monitoring/values.yaml` are worth knowing.
`serviceMonitorSelectorNilUsesHelmValues: false` makes the operator watch every
ServiceMonitor in the cluster instead of only the ones carrying its own release
label, which is the difference between a full target list and a quietly
incomplete one. And `kubeControllerManager`, `kubeScheduler`, `kubeEtcd` and
`kubeProxy` are turned off, because EKS runs the control plane and does not
expose them, so leaving them on gives four targets that sit red forever.

## 5. How the application reaches the database

Nothing about the database is committed. The chain is:

1. `modules/rds` builds the instance and generates the master password.
2. The root `main.tf` writes a Kubernetes Secret named `django-db` in the application namespace, filled from the module outputs.
3. `charts/django-app/values.yaml` names that Secret, and the Deployment reads it with `envFrom`.
4. `django/config/settings.py` reads `POSTGRES_HOST` and the rest, and falls back to a local SQLite file when they are missing, so the image still runs outside the cluster.

The Helm chart therefore never contains a host name or a password, and neither
does the repository. Terraform is the only thing that knows both halves.

```bash
curl "http://$(kubectl get svc django-app-django-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/dbz/"
{"engine": "postgresql", "host": "lesson-8-9-db...rds.amazonaws.com", "ok": true, "detail": "connected"}
```

It returns 503 instead of 200 when the query fails. The probes deliberately do
not use it: a probe that touches the database turns a slow query into a restart
loop.

### The rds module is universal

The same module builds either shape, decided by one flag:

```hcl
module "rds" {
  source = "./modules/rds"

  name       = "lesson-8-9-db"
  use_aurora = false          # true builds an Aurora cluster instead

  engine         = "postgres" # or mysql, aurora-postgresql, aurora-mysql
  engine_version = "16.6"
  instance_class = "db.t3.micro"

  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  allowed_cidr_blocks = [module.vpc.vpc_cidr_block]
}
```

`false` builds an `aws_db_instance`, `true` builds an `aws_rds_cluster` with a
writer and however many readers were asked for. Either way it also builds the DB
subnet group, the security group with its rules, and a parameter group carrying
`max_connections`, `log_statement` and `work_mem`. Terraform has no `if`, so the
switch is `count = var.use_aurora ? 1 : 0` and the branch not taken disappears
from the plan.

The parameter group family is derived rather than asked for, so `postgres` plus
`16.6` becomes `postgres16` and `mysql` plus `8.0.39` becomes `mysql8.0`. On
MySQL the default parameters change too, because `log_statement` and `work_mem`
are PostgreSQL settings that MySQL rejects. Every variable is typed and
described, and five of them validate their input.

Switching the whole database is a change in `terraform.tfvars` only:

```hcl
use_aurora           = true
db_engine            = "aurora-postgresql"
db_instance_class    = "db.t3.medium"   # Aurora refuses anything smaller
aurora_replica_count = 1
```

## Design decisions worth explaining

**Kaniko instead of Docker in Docker.** Building an image inside Kubernetes with
the Docker daemon means mounting the host socket or running a privileged
container, both of which give the build a way out of its own container. Kaniko
builds the layers in userspace, with no daemon and no privileges.

**IRSA instead of an access key.** The Kaniko pod needs to push to ECR. The
obvious way is to put an AWS access key in a Jenkins credential. Instead the
service account carries an `eks.amazonaws.com/role-arn` annotation, EKS injects a
short lived token into the pod, and the SDK exchanges it for temporary
credentials. No long lived key exists anywhere, so there is nothing to leak or
rotate, and the role is scoped to this one ECR repository.

**JCasC instead of clicking through the setup wizard.** The Jenkins
configuration, including the GitHub credential and the seed job, is written by
Terraform. If the Jenkins pod is deleted it comes back configured. Nothing here
depends on somebody remembering what they clicked.

**The database is not reachable from the internet.** It sits in the private
subnets, its security group allows port 5432 from the VPC CIDR and nothing else,
and it is encrypted at rest. The password is generated by Terraform and handed to
the pods through a Secret, so it exists in the state file and in the cluster, and
nowhere else.

**A separate `/healthz/` endpoint.** The probes hit an endpoint that returns 200
and nothing else, while `/dbz/` is where the database check lives. Pointing a
liveness probe at a page that queries a database turns a slow query into a
restart loop, and a restart loop into an outage.

**No NAT gateway.** The nodes are in public subnets. A NAT gateway costs about
$33 a month, and the only thing in the private subnets is RDS, which has no
reason to reach the internet. Moving the node group into the private subnets
later is a one line change, but a NAT gateway has to be added at the same time or
the nodes never become Ready.

## Cost

Roughly, per day: $2.40 for the EKS control plane, $4.30 for two
`m7i-flex.large` nodes, $1.75 for the four load balancers, and small change for
the volumes and ECR storage. The `db.t3.micro` RDS instance is free tier for the
first 750 hours a month. Around **$9 a day**, so do not leave it running.

### Two notes

The account is on the AWS Free Plan, which refuses any instance type that is not
free tier eligible, and the first apply failed on exactly that. The eligible
micro sizes are unusable here, since 1 GiB of RAM is less than Jenkins alone
requests and the VPC CNI allows only 4 pods per node on them, against the roughly
20 this project needs. `m7i-flex.large` gives 8 GiB and about 29 pods.

`git_branch` defaults to `final-project`, so Jenkins builds from this branch and
Argo CD watches it. `project_name` and `cluster_name` still say `lesson-8-9`,
because renaming them would tear the whole environment down and build it again
for nothing but a nicer string.

## Destroy everything

```bash
# Delete the Argo CD Application first. It has a finalizer that cleans up what
# it deployed, including the app load balancer. Skipping this leaves an orphaned
# load balancer that Terraform does not know about and will not delete.
kubectl -n argocd delete application django-app

# Wait for the app load balancer to disappear
kubectl get svc

terraform destroy
```

`terraform destroy` takes care of the other three load balancers, because those
services belong to Helm releases Terraform owns. The RDS instance is deleted with
`skip_final_snapshot = true`, so nothing is kept. Set that variable to `false`
first if the data matters.

If `destroy` hangs on the VPC, it is almost always a load balancer or an ENI that
Kubernetes created and Terraform does not track. Check the EC2 console under Load
Balancers and Network Interfaces, delete what is left, and run `terraform
destroy` again.
