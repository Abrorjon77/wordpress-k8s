# WordPress on Kubernetes: Helm + ArgoCD + Prometheus/Grafana

A learning project on a local **kind** cluster:

1. **Helm:** WordPress + MySQL packaged as a Helm chart.
2. **ArgoCD:** deploys that chart from this GitHub repo automatically (GitOps).
3. **Prometheus, Grafana, Alertmanager:** monitor the cluster and WordPress.

```
GitHub repo ──(ArgoCD watches)──► kind cluster "lab"
                                   ├── namespace wordpress   → WordPress + MySQL   http://localhost:30001
                                   ├── namespace argocd      → ArgoCD UI           https://localhost:8080
                                   └── namespace monitoring  → Grafana             http://localhost:30000
                                                               Prometheus          http://localhost:30090
                                                               Alertmanager        http://localhost:9093
```

---

## Table of contents
- [What's in this repo](#whats-in-this-repo)
- [Prerequisites](#prerequisites)
- [Start from zero](#start-from-zero)
  - [Step 1: Create the kind cluster](#step-1-create-the-kind-cluster)
  - [Step 2: Try the Helm chart by hand (optional)](#step-2-try-the-helm-chart-by-hand-optional)
  - [Step 3: Install ArgoCD](#step-3-install-argocd)
  - [Step 4: Deploy WordPress with ArgoCD](#step-4-deploy-wordpress-with-argocd)
  - [Step 5: Install Prometheus, Grafana, Alertmanager](#step-5-install-prometheus-grafana-alertmanager)
- [Ports and passwords](#ports-and-passwords)
- [Everyday commands](#everyday-commands)
- [Learning exercises](#learning-exercises)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)
- [Delete everything](#delete-everything)
- [Project history: what we did](#project-history-what-we-did)

---

## What's in this repo

```
.
├── README.md
├── kind/
│   └── kind-config.yaml              # kind cluster with ports 30000-30090 forwarded to your Mac
├── wordpress-chart/                  # ⭐ Helm chart for WordPress + MySQL
│   ├── Chart.yaml                    #   chart name and version
│   ├── values.yaml                   #   default settings
│   ├── values-kind.yaml              #   overrides for kind (NodePort 30001, storageClass "standard", no Ingress)
│   └── templates/                    #   Kubernetes YAML with {{ }} placeholders
│       ├── _helpers.tpl              #     shared names and labels
│       ├── secret.yaml               #     MySQL passwords (base64-encoded from values)
│       ├── mysql-deployment.yaml / mysql-service.yaml / mysql-pvc.yaml
│       ├── wordpress-deployment.yaml / wordpress-service.yaml / wordpress-pvc.yaml
│       ├── ingress.yaml              #     only when ingress.enabled=true
│       └── NOTES.txt                 #     shown after install
├── argocd/
│   └── wordpress-app.yaml            # ⭐ ArgoCD Application: "deploy wordpress-chart from GitHub"
├── monitoring/
│   └── kube-prometheus-values.yaml   # ⭐ settings for Prometheus + Grafana + Alertmanager
└── *.yaml (root)                     # the ORIGINAL plain Kubernetes manifests (before Helm). Kept for reference, not used.
```

**Which file do I change?**

| I want to change... | Edit this file | Then |
|---|---|---|
| WordPress or MySQL settings (port, storage, images) | `wordpress-chart/values-kind.yaml` | `git commit` + `git push`. ArgoCD applies it. |
| Where ArgoCD gets the chart, or sync behaviour | `argocd/wordpress-app.yaml` | `kubectl apply -f argocd/wordpress-app.yaml` |
| Prometheus, Grafana, Alertmanager settings | `monitoring/kube-prometheus-values.yaml` | `helm upgrade ...` (see [Step 5](#step-5-install-prometheus-grafana-alertmanager)) |
| Cluster ports | `kind/kind-config.yaml` | Recreate the cluster (ports can't be added to a running kind cluster) |

---

## Prerequisites

Install on macOS:
```bash
brew install kind kubectl helm argocd
```
You also need **Docker Desktop** running, because kind runs Kubernetes inside Docker.

Check:
```bash
docker ps && kind version && kubectl version --client && helm version && argocd version --client
```

---

## Start from zero

> If the `lab` cluster already exists, skip Step 1.
> Check with: `kind get clusters`

### Step 1: Create the kind cluster

```bash
kind create cluster --name lab --config kind/kind-config.yaml
kubectl config use-context kind-lab
kubectl get nodes                 # STATUS should be Ready
kubectl get storageclass          # "standard (default)", used by our PVCs
```

**Why a config file?** The kind "node" is a Docker container. A NodePort Service only reaches your browser if that port is forwarded from the container to your Mac. `kind-config.yaml` forwards **30000, 30001, 30002, 30080, 30090**. Check with:
```bash
docker port lab-control-plane
```

---

### Step 2: Try the Helm chart by hand (optional)

This is how you learn Helm. Skip it if you only want the ArgoCD setup, and **uninstall it before Step 4**.

```bash
helm lint ./wordpress-chart                                                    # check for errors
helm template my-wp ./wordpress-chart -f ./wordpress-chart/values-kind.yaml    # see the YAML, installs nothing

helm install my-wp ./wordpress-chart -f ./wordpress-chart/values-kind.yaml \
  -n wordpress --create-namespace \
  --set wordpress.service.nodePort=30080        # 30080 so it won't clash with ArgoCD's copy on 30001

kubectl get pods -n wordpress -w                # wait for Running, then Ctrl+C
```
Open **http://localhost:30080**.

When you're done:
```bash
helm uninstall my-wp -n wordpress
```

**How the chart works:**
- `values.yaml` holds the defaults, and `values-kind.yaml` overrides some of them for kind.
- Templates use `{{ .Values.xxx }}`. Helm fills them in to produce normal Kubernetes YAML.
- Passwords are plain text in values. `templates/secret.yaml` base64-encodes them with `b64enc`.
- Resource names start with the release name (`my-wp-wordpress`, `my-wp-wordpress-mysql`), so you can install it more than once.
- Changing the passwords restarts the pods automatically, through a `checksum/secret` annotation.

---

### Step 3: Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl get pods -n argocd -w                   # wait for all Running, then Ctrl+C
```

Get the admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

Open the UI. Keep this running in its own terminal:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Go to **https://localhost:8080**, accept the certificate warning, and log in as `admin` with that password.

---

### Step 4: Deploy WordPress with ArgoCD

**The GitOps idea:** Git is the source of truth. You don't run `helm install` anymore. You commit to Git, and ArgoCD makes the cluster match.

1. Make sure your latest changes are on GitHub. ArgoCD reads from GitHub, not from your laptop.
   ```bash
   git push
   ```
2. Create the Application:
   ```bash
   kubectl apply -f argocd/wordpress-app.yaml
   ```
3. Watch it in the UI, or with:
   ```bash
   kubectl get application wordpress -n argocd
   kubectl get pods -n wordpress -w
   ```

Open **http://localhost:30001** and finish the WordPress setup wizard.

**What `argocd/wordpress-app.yaml` says:**

| Field | Meaning |
|---|---|
| `repoURL` / `targetRevision` / `path` | Use the `wordpress-chart/` folder on the `main` branch of this GitHub repo |
| `helm.valueFiles: [values-kind.yaml]` | Use the kind settings |
| `destination.namespace: wordpress` | Deploy into the `wordpress` namespace |
| `CreateNamespace=true` | Create that namespace if it's missing |
| `automated` | Sync automatically when Git changes |
| `prune: true` | Delete things from the cluster that were removed from Git |
| `selfHeal: true` | Undo manual `kubectl` changes |

**Note:** ArgoCD renders the chart itself. `helm list` shows nothing, and the release name is the app name, so the resources are called `wordpress` and `wordpress-mysql`.

**Make a change the GitOps way:**
```bash
# edit wordpress-chart/values-kind.yaml, for example storage size
git commit -am "Describe the change"
git push
# ArgoCD notices within ~3 minutes (or click Refresh in the UI)
```

---

### Step 5: Install Prometheus, Grafana, Alertmanager

One Helm chart, **kube-prometheus-stack**, installs all three:

| Tool | Think of it as | Job |
|---|---|---|
| Prometheus | 📹 camera | Collects and stores metrics |
| Grafana | 📺 TV screen | Shows metrics as dashboards |
| Alertmanager | 🔔 alarm bell | Sends notifications when alerts fire |

**Remember: R V T I C** = **R**epo → **V**alues → **T**est → **I**nstall → **C**heck

**R: Repo** (once per computer)
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

**V: Values.** The only file you edit is `monitoring/kube-prometheus-values.yaml`:

| Setting | Why |
|---|---|
| `grafana.service` → NodePort **30000** | Open Grafana at localhost:30000 |
| `prometheus.service` → NodePort **30090** | Open Prometheus at localhost:30090 |
| `serviceMonitorSelectorNilUsesHelmValues: false` | Prometheus picks up ServiceMonitors from **all** namespaces, not only its own |
| `retention: 2d` | Keep 2 days of data (small, for a laptop) |
| `kubeEtcd`, `kubeControllerManager`, `kubeScheduler`, `kubeProxy` → `enabled: false` | They can't be scraped on kind and would show as permanently DOWN |
| *(no Grafana password)* | Grafana generates one and keeps it in a Secret, so none goes into Git |

To see every available setting (6,000+ lines):
```bash
helm show values prometheus-community/kube-prometheus-stack > /tmp/default-values.yaml
```

**T: Test** (renders only, changes nothing)
```bash
helm template monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/kube-prometheus-values.yaml | grep nodePort
# expect: 30000 and 30090
```

**I: Install**
```bash
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f monitoring/kube-prometheus-values.yaml
```

**C: Check**
```bash
kubectl get pods -n monitoring                  # all Running after 1-2 min
```
- **Grafana:** http://localhost:30000, user `admin`. Get the password with:
  ```bash
  kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
  ```
- **Prometheus:** http://localhost:30090. Go to **Status → Targets**; everything should be UP.
- **Alertmanager:**
  ```bash
  kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093
  ```
  Then open http://localhost:9093.

**Change settings later:** edit the values file, then:
```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/kube-prometheus-values.yaml
```

**What the chart creates:** the Prometheus Operator, new resource types (CRDs) such as `ServiceMonitor` and `PrometheusRule`, Prometheus and Alertmanager (built by the operator), Grafana with about 20 ready-made dashboards, node-exporter, kube-state-metrics, and default alert rules.

---

## Ports and passwords

| What | URL | Login |
|---|---|---|
| WordPress (ArgoCD) | http://localhost:30001 | created in the setup wizard |
| WordPress (manual Helm, Step 2) | http://localhost:30080 | created in the setup wizard |
| ArgoCD | https://localhost:8080 (needs port-forward) | `admin` / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` |
| Grafana | http://localhost:30000 | `admin` / `kubectl get secret -n monitoring monitoring-grafana -o jsonpath="{.data.admin-password}" \| base64 -d` |
| Prometheus | http://localhost:30090 | none |
| Alertmanager | http://localhost:9093 (needs port-forward) | none |

Spare forwarded port: **30002**.

---

## Everyday commands

```bash
# Is everything running?
kubectl get pods -A

# Helm
helm list -A                                    # installed releases (ArgoCD apps don't show here)
helm history <release> -n <ns>                  # revisions
helm rollback <release> <revision> -n <ns>      # go back

# ArgoCD
argocd login localhost:8080 --username admin --insecure
argocd app list
argocd app get wordpress
argocd app diff wordpress
argocd app sync wordpress

# Logs
kubectl logs -n wordpress deploy/wordpress
kubectl logs -n wordpress deploy/wordpress-mysql
```

---

## Learning exercises

**Helm**
1. Change a value with `--set` and compare `helm template` output before and after.
2. **Upgrade and rollback:** move the site to another port with `helm upgrade`, break it by changing `mysql.auth.password`, look at `helm history`, then `helm rollback`.
   (MySQL sets its password only on first start, so changing it later breaks the database connection. It's a classic mistake.)
3. `helm upgrade ... --rollback-on-failure --timeout 2m` with a bad image tag. Helm rolls back on its own.

**ArgoCD**
1. Change `values-kind.yaml`, push, and watch it go OutOfSync, then sync.
2. **Self-heal:** `kubectl delete svc wordpress -n wordpress`. ArgoCD recreates it.
3. **Rollback through Git:** `git revert HEAD && git push`.
4. **Prune:** set `ingress.enabled: true`, push, then set it back to `false` and push. The Ingress is deleted.

**Monitoring**
1. In Grafana, open **Kubernetes / Compute Resources / Namespace (Pods)** and choose `wordpress`.
2. In Prometheus, try these queries:
   ```promql
   up
   sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="wordpress"}[5m]))
   container_memory_working_set_bytes{namespace="wordpress", container!=""}
   kube_pod_container_status_restarts_total{namespace="wordpress"}
   ```
3. `kubectl delete pod -n wordpress -l tier=frontend` and watch the restart appear on the dashboards.

**Next ideas:** a MySQL exporter and `ServiceMonitor`, your own `PrometheusRule` alert, managing monitoring with ArgoCD (it needs the `ServerSide=true` sync option), Sealed Secrets.

---

## Troubleshooting

| Problem | Cause / fix |
|---|---|
| PVC stuck in `Pending` | Wrong storage class. kind uses `standard`, which is set in `values-kind.yaml`. Check with `kubectl get storageclass`. |
| "Error establishing a database connection" | MySQL is still starting (wait about 1 minute), **or** the password was changed after the first install (roll back, or delete the MySQL PVC to start fresh). |
| `localhost:300xx` doesn't open | The port isn't forwarded (`docker port lab-control-plane`), or the Service isn't NodePort (`kubectl get svc -A`). |
| `provided port is already allocated` | Two Services want the same NodePort. Check with `kubectl get svc -A \| grep 300`. |
| ArgoCD doesn't apply your change | You didn't `git push`. ArgoCD reads GitHub. Click **Refresh** in the UI. |
| ArgoCD keeps undoing a manual change | That's `selfHeal: true` working. Change it in Git instead. |
| Prometheus target DOWN | On kind, the control-plane components can't be scraped. That's why they're disabled in the values file. |
| Red errors in VS Code on chart templates | The editor doesn't understand `{{ }}`. Trust `helm lint` instead. |

---

## Security notes

- ⚠️ **This repo is public.** The MySQL passwords in `wordpress-chart/values.yaml` and `wordpress-secret.yaml` are **throwaway learning values**. Never reuse them on a real server.
- Base64 is **not** encryption. Anyone can decode a Kubernetes Secret with `base64 -d`.
- Grafana and ArgoCD passwords are generated inside the cluster and are never stored in Git.
- For real projects, use **Sealed Secrets** or **External Secrets**, and keep secrets out of Git.
- Before every push, check what you're sending:
  ```bash
  git status
  git diff --cached
  ```

---

## Delete everything

Remove the apps but keep the cluster:
```bash
kubectl delete -f argocd/wordpress-app.yaml       # ArgoCD deletes WordPress (prune)
helm uninstall monitoring -n monitoring
kubectl delete namespace monitoring wordpress
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl delete namespace argocd
```

Delete the whole cluster:
```bash
kind delete cluster --name lab
```
Then start again at [Step 1](#step-1-create-the-kind-cluster).

---

## Project history: what we did

1. **Started with plain manifests:** the root `*.yaml` files (WordPress + MySQL Deployments, Services, PVCs, Secret, Ingress).
2. **Converted them into a Helm chart:** `wordpress-chart/`, with passwords, images, storage and ingress moved into `values.yaml`.
3. **Adapted it for kind:** `values-kind.yaml` (storage class `standard`, NodePort, Ingress off) and added a `nodePort` option to the Service template.
4. **Learned Helm:** install, template, upgrade, rollback, history.
5. **Pushed to GitHub** and checked the repo for sensitive data.
6. **Installed ArgoCD** and created `argocd/wordpress-app.yaml`. WordPress now deploys from Git.
7. **Turned on auto-sync, prune and self-heal,** and moved WordPress to port 30001 through a Git commit.
8. **Installed monitoring:** kube-prometheus-stack with `monitoring/kube-prometheus-values.yaml`.
9. **Saved the kind cluster config** (`kind/kind-config.yaml`) so everything can be rebuilt from zero.
