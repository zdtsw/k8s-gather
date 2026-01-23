# k8s-gather

Diagnostic data collection tool for AI/ML workloads on **any Kubernetes cluster** (vanilla K8s, EKS, GKE, AKS, OpenShift, etc.).

Unlike `oc adm must-gather` which is OpenShift-specific, k8s-gather uses standard `kubectl` commands and works on any Kubernetes cluster.

## Features

- Collects namespace resources, pod logs, events, and custom resources
- Supports KServe, KubeRay, Kueue, and infrastructure components (Istio, MetalLB, SR-IOV)
- Works with vanilla Kubernetes (no OpenShift required)
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

> **Note:** Override image with env variable `IMG`.

### Deploy and get to local host

```bash
# Login to your cluster first
# K8s: export KUBECONFIG=/path/to/kubeconfig
# OpenShift: oc login --server=<cluster-api> --token=<token>

# Set namespace where Pod should be running
export NS=k8s-gather

# Update manifests/pod.yaml with your image, then apply
kubectl apply -k manifests/

# Wait for gather to complete
kubectl logs -f k8s-gather-pod -n $NS

# Copy output locally
kubectl cp $NS/k8s-gather-pod:/must-gather ./my-k8s-gather 2>/dev/null | grep -v "tar: Removing"

# Cleanup
kubectl delete -k manifests/
```

> **Note:** To use a different namespace, edit `manifests/namespace.yaml` and set the `NS` variable accordingly.

## Configuration

Set environment variables to customize collection:

| Variable | Default | Description |
|----------|---------|-------------|
| `COMPONENT` | `all` | Component to collect (see below) |
| `ENABLE_SERVING` | `true` | Enable KServe collection (when COMPONENT=all) |
| `ENABLE_KUEUE` | `false` | Enable Kueue collection (when COMPONENT=all) |
| `ENABLE_KUBERAY` | `false` | Enable KubeRay collection (when COMPONENT=all) |
| `OPERATOR_NAMESPACE` | `opendatahub` | KServe namespace |
| `GW_NAMESPACE` | `openshift-ingress` | Gateway namespace |
| `MUST_GATHER_SINCE` | - | Time duration (e.g., `1h`, `30m`) |

### Components

- `all` (default) - Collect all enabled components + infrastructure
- `kserve` - Model Serving (KServe, InferenceServices)
- `kuberay` - Ray clusters
- `kueue` - Workload queuing

Infrastructure components (always collected with `all`):
- Istio service mesh
- MetalLB load balancer, currently it is disabled. We need patch upstream with a fix for the name of deployment
- SR-IOV network operator

## What's Collected

For each namespace:
- Namespace YAML
- All resources (deployments, services, configmaps, secrets, pods, etc.)
- Container logs (current and previous)
- Events

Cluster-scoped resources:
- InferenceServices, ServingRuntimes
- RayClusters, RayJobs
- ClusterQueues, LocalQueues
- Gateway API resources

## Permissions

**Deploying k8s-gather requires cluster-admin permissions** because:
- Creates a ClusterRoleBinding with `cluster-admin` role
- The gather pod needs cluster-wide read access to collect data from all namespaces
