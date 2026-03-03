# Helm Chart for k8s-gather

This directory contains the Helm chart for deploying k8s-gather on Kubernetes clusters.

## Prerequisites

- Kubernetes 1.32+
- Helm 3.0+
- Cluster-admin permissions to deploy (required to create ClusterRoleBinding with `k8s-gather-reader` ClusterRole)
  - Note: The gather pod runs with read-only permissions (get, list, watch)

## Installation

```bash
# Install with default values
helm install k8s-gather ./k8s-gather
```

For advanced configuration options, customize values using `--set` flags or a custom values file. See the Configuration section below.

## Configuration

The following table lists the configurable parameters of the k8s-gather chart and their default values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image repository | `quay.io/wenzhou/k8s-gather` |
| `image.tag` | Container image tag | `v1.2.0` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `namespace.name` | Namespace name | `k8s-gather` |
| `namespace.create` | Create namespace | `false` |
| `serviceAccount.name` | ServiceAccount name | `k8s-gather-sa` |
| `serviceAccount.create` | Create ServiceAccount | `true` |
| `rbac.create` | Create RBAC resources | `true` |
| `pod.name` | Pod name (when useJob=false) | `k8s-gather-pod` |
| `pod.restartPolicy` | Pod restart policy | `Never` |
| `pod.sleepTime` | Time (seconds) to keep pod running after gather completes | `600` |
| **Components** | | |
| `pod.env.enableAll` | Enable all components (overrides individual flags) | `false` |
| `pod.env.enableServing` | Enable KServe/LLM-D collection | `true` |
| `pod.env.enableKueue` | Enable Kueue collection | `false` |
| `pod.env.enableKuberay` | Enable KubeRay collection | `false` |
| `pod.env.enableMaas` | Enable MaaS (Model as a Service) collection | `false` |
| `pod.env.enableWva` | Enable WVA (Workload Variant Autoscaler) collection | `false` |
| `pod.env.enableMonitoring` | Enable Prometheus Operator monitoring collection | `false` |
| **Namespace Overrides** | (auto-detected if not set) | |
| `pod.env.operatorNamespace` | Operator namespace | Not set |
| `pod.env.applicationsNamespace` | Application namespace | Not set |
| `pod.env.istioNamespace` | Istio service mesh namespace | Not set |
| `pod.env.routeNamespace` | OpenShift Routes namespace (OCP only) | Not set |
| `pod.env.kuadrantNamespace` | Kuadrant namespace (OCP only) | Not set |
| `pod.env.monitoringNamespace` | Monitoring namespace for self-hosted Prometheus/Grafana | Not set |
| `pod.env.aksMonitoringType` | Monitoring type: `managed` or `self-hosted` (AKS only) | Not set |
| **Log Collection** | | |
| `pod.env.mustGatherSince` | Time duration for logs (e.g., `1h`, `30m`) | Not set |
| `pod.env.mustGatherSinceTime` | Absolute timestamp for logs (RFC3339 format) | Not set |
| **Job Configuration** | | |
| `useJob` | Use Job instead of Pod | `true` |
| `job.name` | Job name (when useJob=true) | `k8s-gather-job` |
| `job.ttlSecondsAfterFinished` | Auto-cleanup job after completion (seconds) | `600` |

See [values.yaml](k8s-gather/values.yaml) for all available options.

## Collecting Results

```bash
# Wait for collection to complete (when using Job)
POD=$(kubectl get pods -n k8s-gather -l job-name=k8s-gather-job -o jsonpath='{.items[0].metadata.name}')
echo "Waiting for k8s-gather to complete..."
until kubectl logs $POD -n k8s-gather 2>/dev/null | grep -q "DEBUG: Must-gather collection completed"; do
  sleep 20
done
echo "Collection completed!"

# Copy results
kubectl cp k8s-gather/$POD:/must-gather ./my-k8s-gather.local 2>/dev/null | grep -v "tar: Removing"
```

## Uninstallation

```bash
helm uninstall k8s-gather
```

## Upgrading

```bash
# Upgrade with new values
helm upgrade k8s-gather ./k8s-gather --set image.tag=v1.2.0
```
