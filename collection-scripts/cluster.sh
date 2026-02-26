#!/bin/bash
# shellcheck disable=SC1091
# Note: Core cluster resources (PVs, storage classes, etc.) are collected by gather script
# This script collects cluster info, API resources, and detailed node information

source "$(dirname "$0")/common.sh"

dest_dir="${DST_DIR}/cluster-scoped-resources"
mkdir -p "${dest_dir}"

echo "Collecting cluster information..."

# Cluster info (not collected by gather)
$KUBECTL cluster-info > "${dest_dir}/cluster-info.txt" 2>/dev/null

# API resources list (not collected by gather)
$KUBECTL api-resources > "${dest_dir}/api-resources.txt" 2>/dev/null

# Collect detailed node information
node_dir="${dest_dir}/nodes"
mkdir -p "${node_dir}"

echo "Collecting detailed node information..."

for node in $($KUBECTL get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    node_subdir="${node_dir}/${node}"
    mkdir -p "${node_subdir}"

    $KUBECTL get node "$node" -o yaml > "${node_subdir}/node.yaml" 2>/dev/null
done

echo "Additional cluster information collected"
