#!/bin/bash
# Kueue component gathering script - collects Kueue job queueing resources
# shellcheck disable=SC1091
source "$(dirname "$0")/../common.sh"

# Kueue resources (kueue.x-k8s.io)
# https://kueue.sigs.k8s.io/
resources=(
    "clusterqueues.kueue.x-k8s.io"
    "localqueues.kueue.x-k8s.io"
    "workloads.kueue.x-k8s.io"
    "workloadpriorityclasses.kueue.x-k8s.io"
    "resourceflavors.kueue.x-k8s.io"
    "admissionchecks.kueue.x-k8s.io"
    "cohorts.kueue.x-k8s.io"
    "provisioningrequestconfigs.kueue.x-k8s.io"
    "topologies.kueue.x-k8s.io"
)

# MultiKueue resources (multi-cluster job dispatching)
resources+=(
    "multikueueclusters.kueue.x-k8s.io"
    "multikueueconfigs.kueue.x-k8s.io"
)

nslist=$(get_all_namespace "${resources[@]}")

run_k8sgather "$nslist" "${resources[@]}"
