#!/bin/bash
# Leader Worker Set dependency gathering script - collects LWS resources
# shellcheck disable=SC1091
source "$(dirname "$0")/../common.sh"

# Leader Worker Set resources
# https://github.com/kubernetes-sigs/lws
resources=(
    "leaderworkersets.leaderworkerset.x-k8s.io"
)

# OpenShift-specific LWS operator (only on OCP)
if [[ "${K8S_DISTRO}" == "ocp" ]]; then
    resources+=(
        "leaderworkersetoperators.operator.openshift.io"
    )
fi

# Get all namespaces where these resources exist
nslist=$(get_all_namespace "${resources[@]}")

# Run collection across all identified namespaces
run_k8sgather "$nslist" "${resources[@]}"

# Collect LWS operator namespace
kubectl_inspect "namespace/openshift-lws-operator" || echo "WARNING: Namespace openshift-lws-operator not found"
