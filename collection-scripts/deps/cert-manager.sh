#!/bin/bash
# cert-manager dependency gathering script - collects certificate management resources
# shellcheck disable=SC1091
source "$(dirname "$0")/../common.sh"

# cert-manager core resources
# https://cert-manager.io/
resources=(
    "certificates.cert-manager.io"
    "issuers.cert-manager.io"
    "clusterissuers.cert-manager.io"
)

# Get all namespaces where these resources exist
nslist=$(get_all_namespace "${resources[@]}")

# Run collection across all identified namespaces
run_k8sgather "$nslist" "${resources[@]}"
