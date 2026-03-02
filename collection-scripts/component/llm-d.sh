#!/bin/bash
# LLM-D component gathering script - collects KServe and llm-d related resources
# shellcheck disable=SC1091
source "$(dirname "$0")/../common.sh"

# Core KServe resources
resources=(
    "llminferenceserviceconfigs.serving.kserve.io"
    "llminferenceservices.serving.kserve.io"
)

# Gateway API resources (standard Kubernetes)
resources+=(
    "gatewayclasses.gateway.networking.k8s.io"
    "gateways.gateway.networking.k8s.io"
    "httproutes.gateway.networking.k8s.io"
    "grpcroutes.gateway.networking.k8s.io"
    "referencegrants.gateway.networking.k8s.io"
)

# Gateway API Inference Extension (inference.networking.x-k8s.io)
# https://gateway-api-inference-extension.sigs.k8s.io/
resources+=(
    "inferencepools.inference.networking.k8s.io"
    "inferencemodelrewrites.inference.networking.x-k8s.io"
    "inferenceobjectives.inference.networking.x-k8s.io"
    "inferencemodels.inference.networking.x-k8s.io"  # to be deleted
)

# Get all namespaces where these resources exist
nslist=$(get_all_namespace "${resources[@]}")

# Run collection across all identified namespaces
run_k8sgather "$nslist" "${resources[@]}"
