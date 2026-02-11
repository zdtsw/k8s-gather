#!/bin/bash
# Environment variables and configuration for k8s-gather

# Do not change this value, upstream hardcode it, change here might cause problem
export DST_DIR="/must-gather"

# Use kubectl (or oc if available when we change base image)
if command -v oc &> /dev/null; then
    export KUBECTL="oc"
else
    export KUBECTL="kubectl"
fi

# Detect xKS distro
function detect_k8s_distro() {
    local distro="other" # the rest from ocp, cks and aks for now.
    local kernel_version os_image provider_id

    kernel_version=$($KUBECTL get nodes -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}' 2>/dev/null) # for CKS
    os_image=$($KUBECTL get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}' 2>/dev/null)  # for OCP
    provider_id=$($KUBECTL get nodes -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null) # for AKS

    # Check for OpenShift first (catches ROSA and ARO)
    if echo "$os_image" | grep -q "Red Hat Enterprise Linux CoreOS"; then
        distro="ocp"
    # Check API resources for OpenShift (fallback)
    elif $KUBECTL api-resources 2>/dev/null | grep -q "route.openshift.io"; then
        distro="ocp"
    # Check kernel version for CoreWeave
    elif echo "$kernel_version" | grep -qi "coreweave"; then
        distro="cks"
    # Check for Azure Kubernetes Service (after OCP to avoid ARO confusion)
    elif echo "$provider_id" | grep -q "^azure://"; then
        distro="aks"
    fi

    echo "$distro"
}

# Initialize distro detection and export for use in all scripts
export K8S_DISTRO=$(detect_k8s_distro)

# Standard Gateway API resources (optional but available across distributions)
GATEWAY_API_RESOURCES=(
    "gatewayclasses.gateway.networking.k8s.io"
    "gateways.gateway.networking.k8s.io"
    "httproutes.gateway.networking.k8s.io"
    "grpcroutes.gateway.networking.k8s.io"
    "referencegrants.gateway.networking.k8s.io"
)

# Istio-specific resources (only collected if Istio is installed)
ISTIO_RESOURCES=(
    "envoyfilters.networking.istio.io"
    "destinationrules.networking.istio.io"
    "virtualservices.networking.istio.io"
    "gateways.networking.istio.io"
)

# Build DEFAULT_RESOURCES based on what's available
DEFAULT_RESOURCES=("${GATEWAY_API_RESOURCES[@]}")

# Add Istio resources if Istio is detected
if $KUBECTL api-resources 2>/dev/null | grep -q "networking.istio.io"; then
    DEFAULT_RESOURCES+=("${ISTIO_RESOURCES[@]}")
fi

# Note: No need to export arrays - all scripts source this file and run in the same shell

# Source distribution-specific configuration
DISTRO_FILE="$(dirname "${BASH_SOURCE[0]}")/distro/${K8S_DISTRO}.sh"
if [ -f "${DISTRO_FILE}" ]; then
    source "${DISTRO_FILE}"
else
    # Fallback to other.sh for unknown distributions
    source "$(dirname "${BASH_SOURCE[0]}")/distro/other.sh"
fi
