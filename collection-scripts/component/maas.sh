#!/bin/bash
# LLM-D component gathering script - collects MAAS related resources
# shellcheck disable=SC1091
source "$(dirname "$0")/../common.sh"

# Kuadrant/MaaS (Model as a Service)
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

# Get all namespaces where these resources exist
nslist=$(get_all_namespace "${resources[@]}")

# Run collection across all identified namespaces
run_k8sgather "$nslist" "${resources[@]}"

# Collect Kuadrant namespace (only on OCP)
if [[ "${K8S_DISTRO}" == "ocp" ]]; then
    KUADRANT_NS=${KUADRANT_NAMESPACE:-kuadrant-system}
    kubectl_inspect "namespace/$KUADRANT_NS" || echo "Namespace ${KUADRANT_NS} not found"
fi
