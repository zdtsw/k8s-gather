#!/bin/bash
# LLM-D component gathering script - collects workload-variant-autoscaler and related resources
# shellcheck disable=SC1091
source "$(dirname "$0")/../common.sh"

# KEDA (Kubernetes Event Driven Autoscaling) + WVA
resources+=(
    "scaledobjects.keda.sh"
    "scaledjobs.keda.sh"
    "triggerauthentications.keda.sh"
    "clustertriggerauthentications.keda.sh"
    "variantautoscalings.llmd.ai"
)              

# Get all namespaces where these resources exist
nslist=$(get_all_namespace "${resources[@]}")

# Run collection across all identified namespaces
run_k8sgather "$nslist" "${resources[@]}"
