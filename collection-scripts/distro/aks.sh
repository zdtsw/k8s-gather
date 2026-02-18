#!/bin/bash
# Azure Kubernetes Service (AKS) specific configuration

# Default Istio namespace (used for gateway and service mesh)
export DEFAULT_ISTIO_NS="istio-system"

# Default monitoring namespace (user-installed kube-prometheus-stack)
export DEFAULT_MONITORING_NS="monitoring"

# Additional AKS-specific configurations can go here
