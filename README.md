# k8s-gather

Diagnostic data collection tool for AI/ML workloads on **any Kubernetes cluster** (vanilla K8s, EKS, GKE, AKS, CoreWeave, OpenShift, etc.).

Unlike `oc adm must-gather` which is OpenShift-specific, k8s-gather uses standard `kubectl` commands and works on any Kubernetes cluster. It automatically detects your Kubernetes distribution and adapts collection accordingly.

## Features

- **Multi-Distribution Support**: Automatically detects and adapts to OpenShift (OCP), CoreWeave (CKS), Azure Kubernetes Service (AKS), and vanilla Kubernetes
- **Modular Components**: KServe/LLM-D, KubeRay, Kueue with selective collection
- **Always-On Dependencies**: Automatically collects cert-manager, Istio (Sail Operator), and Leader Worker Set resources
- **Infrastructure Collection**: Gathers Istio, SR-IOV, and other infrastructure components using upstream must-gather scripts
- **Distribution-Aware**: Collects OpenShift-specific resources (Routes, Kuadrant) only when on OCP
- Runs as a Pod in-cluster with proper RBAC

## Quick Start

```bash
# Install from quay registry
helm install k8s-gather oci://quay.io/wenzhou/charts/k8s-gather \
  --version 1.0.0 -n k8s-gather --create-namespace

# Wait for completion
kubectl wait --for=condition=complete job/k8s-gather-job -n k8s-gather --timeout=5m

# Copy results locally
POD=$(kubectl get pods -n k8s-gather -l job-name=k8s-gather-job -o jsonpath='{.items[0].metadata.name}')
kubectl cp k8s-gather/$POD:/must-gather ./my-k8s-gather

# Cleanup
helm uninstall k8s-gather -n k8s-gather && kubectl delete namespace k8s-gather
```

**Upgrade to a new version:**
```bash
+# Default (Job): delete job first, then upgrade (Jobs are immutable)
+kubectl delete job k8s-gather-job -n k8s-gather && \
+helm upgrade k8s-gather oci://quay.io/wenzhou/charts/k8s-gather --version <new-version> -n k8s-gather
+
+# If using Pod (--set useJob=false): upgrade in place
helm upgrade k8s-gather oci://quay.io/wenzhou/charts/k8s-gather --version <new-version> -n k8s-gather
```

**Enable additional components:**
```bash
# All components (KServe/LLM-D + Kueue + KubeRay)
--set pod.env.enableAll=true

# Specific components
--set pod.env.enableKueue=true --set pod.env.enableKuberay=true
```

> **Prefer Kustomize?** See [Local Development](#local-development) for deployment using [deploy/manifests/](deploy/manifests/).

## Configuration

**Kustomize**: Edit environment variables in [deploy/manifests/job.yaml](deploy/manifests/job.yaml)
**Helm**: Use `--set` flags (e.g., `--set pod.env.enableKueue=true`) or see [deploy/helm/README.md](deploy/helm/README.md)

Available configuration options:

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_ALL` | `false` | Collect all components (overrides individual ENABLE_* flags) |
| `ENABLE_SERVING` | `true` | Enable KServe/LLM-D collection (when ENABLE_ALL=false) |
| `ENABLE_KUEUE` | `false` | Enable Kueue collection (when ENABLE_ALL=false) |
| `ENABLE_KUBERAY` | `false` | Enable KubeRay collection (when ENABLE_ALL=false) |
| `OPERATOR_NAMESPACE` | *auto-detected* | Operator namespace (opendatahub-operator or rhods-operator, fallback: redhat-ods-operator) |
| `APPLICATIONS_NAMESPACE` | *auto-mapped* | Application namespace (mapped from operator namespace, or override) |
| `ISTIO_NAMESPACE` | `istio-system` | Istio service mesh namespace (all distributions) |
| `ROUTE_NAMESPACE` | `openshift-ingress` | OpenShift Routes namespace (OCP only) |
| `KUADRANT_NAMESPACE` | `kuadrant-system` | Kuadrant namespace (OCP only) |
| `MUST_GATHER_SINCE` | - | Time duration for logs (e.g., `1h`, `30m`) |
| `MUST_GATHER_SINCE_TIME` | - | Absolute timestamp for logs (RFC3339 format) |

### Components

By default, only KServe/LLM-D is collected (`ENABLE_SERVING=true`). You can:
- Set `ENABLE_ALL=true` to collect all components (KServe/LLM-D, Kueue, KubeRay)
- Or individually enable components with `ENABLE_KUEUE=true` and/or `ENABLE_KUBERAY=true`

Available components:
- **KServe/LLM-D** - Model Serving (KServe, LLM-D, Gateway API Inference Extension)
- **KubeRay** - Ray distributed compute clusters (requires KubeRay operator installed)
- **Kueue** - Job queueing and workload management (requires Kueue operator installed)

> **Note:** Component collection requires the respective operators to be installed in your cluster. k8s-gather will only collect resources that exist.

**Dependency operators** (always collected):
- **cert-manager** - Certificate management (certificates, issuers, clusterissuers)
- **Sail Operator** - Istio lifecycle management (istios, istiorevisions, istiocnis)
- **Leader Worker Set** - LWS resources (leaderworkersets, and leaderworkersetoperators on OCP)

**Infrastructure components** (always collected, using upstream must-gather scripts):
- **Istio** - Service mesh resources
- **SR-IOV** - Network operator resources
- **MetalLB** - Currently disabled (upstream issue with deployment name)

## What's Collected

### Dependency Operators
- **cert-manager**: Certificate management resources
- **Sail Operator**: Istio lifecycle management
- **Leader Worker Set**: Distributed workload coordination (includes OCP operator)

### Infrastructure (via upstream must-gather scripts)
- **Istio**: Service mesh resources
- **SR-IOV**: Network operator resources
- **MetalLB**: Bare metal load balancer (currently disabled due to upstream issue)

### ODH/RHOAI Platform
- Data Science Cluster initialization and configuration
- Platform component operators (KServe, Kueue, Ray)

## Distribution Support

k8s-gather automatically detects your Kubernetes distribution and adapts resource collection:

| Distribution | Distribution-Specific Features | Status |
|--------------|--------------------------------|--------|
| **OpenShift (OCP)** | Routes, Kuadrant, OpenShift-specific operators | ✅ Supported |
| **CoreWeave (CKS)** | Standard features (custom features planned) | ✅ Supported |
| **Azure (AKS)** | Standard features (custom features planned) | ✅ Supported |
| **Other** (GKE, EKS, vanilla K8s) | Standard features only | 🚧 Planned to be added in future release |

## Local Development

For contributors who want to build and test locally:

### Build and push image

```bash
# Build and push to your registry
make image-build image-push IMG=quay.io/$USER/k8s-gather IMG_VERSION=dev

# Build with custom kubectl version or upstream commit
make image-build KUBECTL_VERSION=v1.32.0 UPSTREAM_COMMIT=<commit-hash>
```

**Available build variables:**
- `IMG` - Container image name (default: `quay.io/$USER/k8s-gather`)
- `IMG_VERSION` - Image tag (default: `v1.0.0`)
- `IMAGE_BUILDER` - Builder tool: `podman` or `docker` (default: `podman`)
- `KUBECTL_VERSION` - kubectl version (default: `v1.31.4`)
- `UPSTREAM_COMMIT` - [must-gather](https://github.com/openshift/must-gather) commit hash (default: `bd9f061`)

### Build and push Helm chart

```bash
# Package and push chart to your registry
make helm-push HELM_REGISTRY=oci://quay.io/$USER/charts
```

### Deploy from local filesystem

**Using Kustomize:**
```bash
# Edit deploy/manifests/job.yaml to set your image
kubectl apply -k deploy/manifests/
kubectl wait --for=condition=complete job/k8s-gather-job -n k8s-gather --timeout=5m
POD=$(kubectl get pods -n k8s-gather -l job-name=k8s-gather-job -o jsonpath='{.items[0].metadata.name}')
kubectl cp k8s-gather/$POD:/must-gather ./my-k8s-gather
kubectl delete -k deploy/manifests/
```

**Using Helm:**
```bash
# Deploy from local chart directory
helm install k8s-gather ./deploy/helm/k8s-gather -n k8s-gather --create-namespace \
  --set image.repository=quay.io/$USER/k8s-gather --set image.tag=dev
kubectl wait --for=condition=complete job/k8s-gather-job -n k8s-gather --timeout=5m
POD=$(kubectl get pods -n k8s-gather -l job-name=k8s-gather-job -o jsonpath='{.items[0].metadata.name}')
kubectl cp k8s-gather/$POD:/must-gather ./my-k8s-gather
helm uninstall k8s-gather -n k8s-gather
```

## Permissions

**Deploying k8s-gather requires cluster-admin permissions** because:
- Creates a ClusterRoleBinding with `cluster-admin` role
- The gather pod needs cluster-wide read access to collect data from all namespaces
