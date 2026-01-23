#!/bin/bash
# shellcheck disable=SC2034,SC2086,SC2001,SC2068,SC2153
# k8s-gather: Compatible with vanilla Kubernetes (kubectl-based)

# Do not change this value, upstream hardcode it, change here might cause problem
export DST_DIR="/must-gather"

# Use kubectl (or oc if available when we change base image)
if command -v oc &> /dev/null; then
    KUBECTL="oc"
else
    KUBECTL="kubectl"
fi

# Default resources to collect for every namespace (Gateway API, Istio, etc.)
DEFAULT_RESOURCES=(
    "gateways.gateway.networking.k8s.io"
    "httproutes.gateway.networking.k8s.io"
    "grpcroutes.gateway.networking.k8s.io"
    "referencegrants.gateway.networking.k8s.io"
    "envoyfilters"
    "destinationrules"
)

# kubectl-based replacement for 'oc adm inspect'
# Collects: namespace yaml, all resources, pod logs, events
function kubectl_inspect() {
    local resource="$1"
    local namespace="$2"
    local dest_dir="${DST_DIR}"

    # Handle namespace/name format
    if [[ "$resource" == namespace/* ]]; then
        namespace="${resource#namespace/}"
        resource="namespace"
    fi

    if [[ "$resource" == "namespace" ]] && [[ -n "$namespace" ]]; then
        local ns_dir="${dest_dir}/namespaces/${namespace}"
        mkdir -p "${ns_dir}/pods" "${ns_dir}/core" "${ns_dir}/apps" "${ns_dir}/events"

        # Get namespace yaml
        $KUBECTL get namespace "$namespace" -o yaml > "${ns_dir}/${namespace}.yaml" 2>/dev/null

        # Get all resources in namespace
        $KUBECTL get all -n "$namespace" -o yaml > "${ns_dir}/core/all.yaml" 2>/dev/null
        $KUBECTL get configmaps -n "$namespace" -o yaml > "${ns_dir}/core/configmaps.yaml" 2>/dev/null
        $KUBECTL get secrets -n "$namespace" -o yaml > "${ns_dir}/core/secrets.yaml" 2>/dev/null
        $KUBECTL get services -n "$namespace" -o yaml > "${ns_dir}/core/services.yaml" 2>/dev/null
        $KUBECTL get endpoints -n "$namespace" -o yaml > "${ns_dir}/core/endpoints.yaml" 2>/dev/null
        $KUBECTL get pvc -n "$namespace" -o yaml > "${ns_dir}/core/persistentvolumeclaims.yaml" 2>/dev/null
        $KUBECTL get deployments -n "$namespace" -o yaml > "${ns_dir}/apps/deployments.yaml" 2>/dev/null
        $KUBECTL get statefulsets -n "$namespace" -o yaml > "${ns_dir}/apps/statefulsets.yaml" 2>/dev/null
        $KUBECTL get daemonsets -n "$namespace" -o yaml > "${ns_dir}/apps/daemonsets.yaml" 2>/dev/null
        $KUBECTL get replicasets -n "$namespace" -o yaml > "${ns_dir}/apps/replicasets.yaml" 2>/dev/null
        $KUBECTL get roles -n "$namespace" -o yaml > "${ns_dir}/core/roles.yaml" 2>/dev/null
        $KUBECTL get rolebindings -n "$namespace" -o yaml > "${ns_dir}/core/rolebindings.yaml" 2>/dev/null
        $KUBECTL get routes -n "$namespace" -o yaml > "${ns_dir}/core/routes.yaml" 2>/dev/null

        # Get events
        $KUBECTL get events -n "$namespace" -o yaml > "${ns_dir}/events/events.yaml" 2>/dev/null

        # Get pod logs
        for pod in $($KUBECTL get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            local pod_dir="${ns_dir}/pods/${pod}"
            mkdir -p "${pod_dir}"
            $KUBECTL get pod "$pod" -n "$namespace" -o yaml > "${pod_dir}/${pod}.yaml" 2>/dev/null
            $KUBECTL describe pod "$pod" -n "$namespace" > "${pod_dir}/${pod}-describe.txt" 2>/dev/null

            # Get logs for each container
            for container in $($KUBECTL get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null); do
                mkdir -p "${pod_dir}/${container}/logs"
                $KUBECTL logs "$pod" -n "$namespace" -c "$container" $log_collection_args > "${pod_dir}/${container}/logs/current.log" 2>/dev/null
                $KUBECTL logs "$pod" -n "$namespace" -c "$container" --previous $log_collection_args > "${pod_dir}/${container}/logs/previous.log" 2>/dev/null
            done
        done

        echo "Gathered data for ns/${namespace}"
    elif [[ -n "$namespace" ]]; then
        # Collect specific resource type in namespace
        local res_name="${resource##*/}"  # extract name after last /
        local res_dir="${dest_dir}/namespaces/${namespace}/${resource}"
        mkdir -p "${res_dir}"
        $KUBECTL get "$resource" -n "$namespace" -o yaml > "${res_dir}/${res_name}.yaml" 2>/dev/null
    else
        # Cluster-scoped resource
        local res_name="${resource##*/}"  # extract name after last /
        local res_dir="${dest_dir}/cluster-scoped-resources/${resource}"
        mkdir -p "${res_dir}"
        $KUBECTL get "$resource" -o yaml > "${res_dir}/${res_name}.yaml" 2>/dev/null
    fi
}

# run gather in the namespaces one by one, also collecting custom resources
function run_k8sgather() {
    local namespaces="$1"
    shift
    local resources=("${DEFAULT_RESOURCES[@]}" "$@")

    for ns in $namespaces; do
        kubectl_inspect "namespace/$ns" || echo "Error inspecting namespace/$ns"
        # Inspect custom resources in this namespace
        for resource in "${resources[@]}"; do
            kubectl_inspect "$resource" "$ns" 2>/dev/null
        done
    done
}

# get the list of namespaces where defined resources exist
function get_all_namespace() {
    local nslist
    for kind in "$@"; do
        nslist+=$($KUBECTL get "$kind" --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{end}' 2>/dev/null)
    done
    uniq_list "$nslist"
}

# remove duplicated namespaces
function uniq_list() {
    echo "$@" | tr ' ' '\n' | sort -u | tr '\n' ' '
}

# get operator version (generic - tries common patterns)
function get_operator_version() {
    local namespace="$1"
    local version=""

    # Try to get version from deployment labels
    version=$($KUBECTL get deployments -n "$namespace" -o jsonpath='{.items[0].metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null)

    if [ -z "$version" ]; then
        version="Unknown"
    fi

    echo "RHOAI version: $version"
}

function get_operator_resource() {
    for k in $@; do
        kubectl_inspect "$k" || echo "Error collecting $k"
    done
}

# Get operator namespace by looking for deployments with specific labels
function get_operator_ns() {
    local operator_name="$1"

    # Try to find by subscription (OCP)
    if command -v oc &> /dev/null; then
        operator_ns=$($KUBECTL get subs -A -o jsonpath="{.items[?(@.spec.name==\"${operator_name}\")].metadata.namespace}" 2>/dev/null)
    fi

    # Fallback: search by deployment name pattern
    if [ -z "${operator_ns}" ]; then
        operator_ns=$($KUBECTL get deployments -A -o jsonpath="{.items[?(@.metadata.name==\"${operator_name}\")].metadata.namespace}" 2>/dev/null)
    fi

    if [ -z "${operator_ns}" ]; then
        echo "INFO: ${operator_name} not detected. Skipping."
        exit 0
    fi

    if [[ "$(echo "${operator_ns}" | wc -w)" -gt 1 ]]; then
        echo "ERROR: found more than one ${operator_name}. Exiting."
        exit 1
    fi
}

# Handle --since and --since-time arguments
get_log_collection_args() {
    log_collection_args=""

    if [ -n "${MUST_GATHER_SINCE:-}" ]; then
        log_collection_args="--since=${MUST_GATHER_SINCE}"
    fi
    if [ -n "${MUST_GATHER_SINCE_TIME:-}" ]; then
        log_collection_args="--since-time=${MUST_GATHER_SINCE_TIME}"
    fi
}
