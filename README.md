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

## How to

### Build and push image

Skip this step if using a pre-built image.

```bash
# Build and push (default: podman, quay.io/$USER/k8s-gather)
make build-and-push

# Or use docker
make build-and-push IMAGE_BUILDER=docker
```

> **Note:** Override image with env variable `IMG` in the Makefile.

### Deploy and get to local host

```bash
# Login to your cluster first
# K8s: export KUBECONFIG=/path/to/kubeconfig
# OpenShift: oc login --server=<cluster-api> --token=<token>

# Update deploy/manifests/pod.yaml:
#   - Line 9: Set your container image
#   - Lines 10-28: Adjust environment variables as needed (see Configuration section)
#   - Default: Only KServe/LLM-D collection is enabled (ENABLE_SERVING=true)
kubectl apply -k deploy/manifests/

# Wait for gather to complete
kubectl logs -f k8s-gather-pod -n k8s-gather

# Copy output locally
kubectl cp k8s-gather/k8s-gather-pod:/must-gather ./my-k8s-gather 2>/dev/null | grep -v "tar: Removing"

# Cleanup
kubectl delete -k deploy/manifests/
```

> **Note:** To use a different namespace, edit the namespace name in `deploy/manifests/namespace.yaml`. Kustomize will automatically update all resources to use that namespace.

## Configuration

Set environment variables to customize collection:

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPONENT` | `all` | Component to collect (see Components section) |
| `ENABLE_SERVING` | `true` | Enable KServe/LLM-D collection (when COMPONENT=all) |
| `ENABLE_KUEUE` | `false` | Enable Kueue collection (when COMPONENT=all) |
| `ENABLE_KUBERAY` | `false` | Enable KubeRay collection (when COMPONENT=all) |
| `OPERATOR_NAMESPACE` | *auto-detected* | Operator namespace (opendatahub-operator or rhods-operator, fallback: redhat-ods-operator) |
| `APPLICATIONS_NAMESPACE` | *auto-mapped* | Application namespace (mapped from operator namespace, or override) |
| `ISTIO_NAMESPACE` | `istio-system` | Istio service mesh namespace (all distributions) |
| `ROUTE_NAMESPACE` | `openshift-ingress` | OpenShift Routes namespace (OCP only) |
| `KUADRANT_NAMESPACE` | `kuadrant-system` | Kuadrant namespace (OCP only) |
| `MUST_GATHER_SINCE` | - | Time duration for logs (e.g., `1h`, `30m`) |
| `MUST_GATHER_SINCE_TIME` | - | Absolute timestamp for logs (RFC3339 format) |

### Components

- `all` (default) - Collect all enabled components + dependencies + infrastructure
- `llm-d` or `kserve` - Model Serving (KServe, LLM-D, Gateway API Inference Extension)
- `kuberay` - Ray distributed compute clusters (requires KubeRay operator installed)
- `kueue` - Job queueing and workload management (requires Kueue operator installed)

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


## Permissions

**Deploying k8s-gather requires cluster-admin permissions** because:
- Creates a ClusterRoleBinding with `cluster-admin` role
- The gather pod needs cluster-wide read access to collect data from all namespaces
