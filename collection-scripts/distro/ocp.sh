#!/bin/bash
# OpenShift (OCP) specific configuration

# Default Istio namespace
export DEFAULT_ISTIO_NS="istio-system"

# Default monitoring namespace (OpenShift built-in monitoring)
export DEFAULT_MONITORING_NS="openshift-monitoring"

# Route namespace (OpenShift Routes)
export ROUTE_NS=${ROUTE_NAMESPACE:-openshift-ingress}

# Additional OCP-specific configurations can go here
