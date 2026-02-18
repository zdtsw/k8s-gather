#!/bin/bash
# Default configuration for other/unknown distro: gke etc

# Default Istio namespace (used for gateway and service mesh)
export DEFAULT_ISTIO_NS="istio-system"

# Default monitoring namespace (user-installed kube-prometheus-stack)
export DEFAULT_MONITORING_NS="monitoring"

# Additional default configurations can go here
