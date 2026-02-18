# Helm Chart for k8s-gather

This directory contains the Helm chart for deploying k8s-gather on Kubernetes clusters.

## Prerequisites

- Kubernetes 1.32+
- Helm 3.0+
- Cluster-admin permissions (required for ClusterRoleBinding)

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
| `namespace.create` | Create namespace | `true` |
| `serviceAccount.name` | ServiceAccount name | `k8s-gather-sa` |
| `serviceAccount.create` | Create ServiceAccount | `true` |
| `rbac.create` | Create RBAC resources | `true` |
| `pod.name` | Pod name (when useJob=false) | `k8s-gather-pod` |
| `pod.restartPolicy` | Pod restart policy | `Never` |
| `pod.sleepTime` | Time (seconds) to keep pod running after gather completes | `600` |
| `pod.env.enableAll` | Enable all components (overrides individual flags) | `false` |
| `pod.env.enableServing` | Enable KServe/LLM-D collection | `true` |
| `pod.env.enableKueue` | Enable Kueue collection | `false` |
| `pod.env.enableKuberay` | Enable KubeRay collection | `false` |
| `pod.env.enableMonitoring` | Enable Prometheus Operator monitoring collection | `true` |
| `pod.env.monitoringNamespace` | Monitoring namespace for self-hosted Prometheus/Grafana (optional, auto-detected by distro) | Not set |
| `pod.env.aksMonitoringType` | Monitoring type: `managed` (Azure Managed Prometheus) or `self-hosted` (kube-prometheus-stack) (AKS only) | Not set |
| `useJob` | Use Job instead of Pod | `true` |
| `job.name` | Job name (when useJob=true) | `k8s-gather-job` |
| `job.ttlSecondsAfterFinished` | Auto-cleanup job after completion (seconds) | Not set (no auto-cleanup) |

See [values.yaml](k8s-gather/values.yaml) for all available options.

## Collecting Results

```bash
# Wait for completion
kubectl logs -f k8s-gather-pod -n k8s-gather

# Copy results
kubectl cp k8s-gather/k8s-gather-pod:/must-gather ./my-k8s-gather 2>/dev/null | grep -v "tar: Removing"
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
