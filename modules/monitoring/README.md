# `monitoring`

Prometheus, Grafana and the rest of kube-prometheus-stack, in the `monitoring`
namespace.

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

## Open Grafana

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

## What to look at

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
