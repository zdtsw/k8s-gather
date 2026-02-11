#!/bin/bash
# shellcheck disable=SC1091
source "$(dirname "$0")/../functions.sh"
resources=("rayclusters" "rayjobs" "rayservices")

nslist=$(get_all_namespace "${resources[@]}")

run_k8sgather "$nslist" "${resources[@]}"
