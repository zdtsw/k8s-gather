#!/bin/bash
# LLM-D component gathering script - collects KServe and related resources
# shellcheck disable=SC1091
source "$(dirname "$0")/../common.sh"

# Core KServe resources
resources=(
    "inferenceservices.serving.kserve.io"
    "inferencegraphs.serving.kserve.io"
    "trainedmodels.serving.kserve.io"
    "servingruntimes.serving.kserve.io"
    "clusterstoragecontainers.serving.kserve.io"
    "predictors.serving.kserve.io"
    "localmodelnodegroups.serving.kserve.io"
)

# LLM-D specific resources
# https://github.com/llm-d-incubation
resources+=(
    "llminferenceserviceconfigs.llmd.ai"
    "llminferenceservices.llmd.ai"
)

# Gateway API Inference Extension (inference.networking.x-k8s.io)
# https://gateway-api-inference-extension.sigs.k8s.io/
resources+=(
    "inferencepools.inference.networking.k8s.io"
    "inferencemodelrewrites.inference.networking.x-k8s.io"
    "inferenceobjectives.inference.networking.x-k8s.io"
)

# NVIDIA NIM (NVIDIA Inference Microservices)
resources+=(
    "accounts.nim.opendatahub.io"
)

# Kuadrant/MaaS (Multi-tenant API Security)
resources+=(
    "ratelimitpolicies.kuadrant.io"
    "kuadrants.kuadrant.io"
    "tokenratelimitpolicies.kuadrant.io"
    "authpolicies.kuadrant.io"
)

# Authorino (Auth/AuthZ)
resources+=(
    "authconfigs.authorino.kuadrant.io"
    "authorinos.operator.authorino.kuadrant.io"
)

# KEDA (Kubernetes Event Driven Autoscaling)
resources+=(
    "scaledobjects.keda.sh"
    "scaledjobs.keda.sh"
    "triggerauthentications.keda.sh"
    "clustertriggerauthentications.keda.sh"
    "variantautoscalings.llmd.ai"                           # workload-variant-autoscaler
)

# OpenShift-specific Kueue operator (only on OCP)
# https://github.com/openshift/kueue-operator
if [[ "${K8S_DISTRO}" == "ocp" ]]; then
    resources+=(
        "kueues.kueue.openshift.io"
    )
fi

# Get all namespaces where these resources exist
nslist=$(get_all_namespace "${resources[@]}")

# Run collection across all identified namespaces
run_k8sgather "$nslist" "${resources[@]}"

# Collect Kuadrant namespace (only on OCP)
if [[ "${K8S_DISTRO}" == "ocp" ]]; then
    KUADRANT_NS=${KUADRANT_NAMESPACE:-kuadrant-system}
    kubectl_inspect "namespace/$KUADRANT_NS" || echo "Namespace ${KUADRANT_NS} not found"
fi
