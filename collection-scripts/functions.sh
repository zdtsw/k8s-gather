#!/bin/bash
# shellcheck disable=SC2034,SC2086,SC2001,SC2068,SC2153
# k8s-gather: Compatible with vanilla Kubernetes (kubectl-based)

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Note: common.sh sources this file, so we don't source common.sh here to avoid circular dependency

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
        # Check if namespace exists first
        if ! $KUBECTL get namespace "$namespace" &>/dev/null; then
            echo "WARNING: Namespace $namespace does not exist, skipping"
            return 1
        fi

        echo "Gathered data for ns/${namespace}"
        local ns_dir="${dest_dir}/namespaces/${namespace}"
        mkdir -p "${ns_dir}"

        # Get namespace yaml
        $KUBECTL get namespace "$namespace" -o yaml > "${ns_dir}/${namespace}.yaml" 2>/dev/null

        # Auto-discover all namespaced resources
        auto_discover_resources "true" "${ns_dir}" "${namespace}"

        # Get pod logs
        for pod in $($KUBECTL get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            local pod_dir="${ns_dir}/pods/${pod}"
            mkdir -p "${pod_dir}"
            $KUBECTL get pod "$pod" -n "$namespace" -o yaml > "${pod_dir}/${pod}.yaml" 2>/dev/null

            # Get logs for each container
            for container in $($KUBECTL get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null); do
                mkdir -p "${pod_dir}/${container}/logs"
                # shellcheck disable=SC2086
                $KUBECTL logs "$pod" -n "$namespace" -c "$container" $log_collection_args > "${pod_dir}/${container}/logs/current.log" 2>/dev/null || true
                # shellcheck disable=SC2086
                $KUBECTL logs "$pod" -n "$namespace" -c "$container" --previous $log_collection_args > "${pod_dir}/${container}/logs/previous.log" 2>/dev/null || true
            done
        done
        return 0
    elif [[ -n "$namespace" ]]; then
        # Collect specific resource type in namespace
        local res_name="${resource##*/}"  # extract name after last /
        local res_dir="${dest_dir}/namespaces/${namespace}/${resource}"
        mkdir -p "${res_dir}"
        $KUBECTL get "$resource" -n "$namespace" -o yaml > "${res_dir}/${res_name}.yaml" 2>/dev/null
        return 0
    fi
    return 0
}

# run gather in the namespaces one by one, also collecting custom resources
function run_k8sgather() {
    local namespaces="$1"
    shift
    local resources=("${DEFAULT_RESOURCES[@]}" "$@")

    for ns in $namespaces; do
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

    echo "RHAII version: $version"
}

# Get operator namespace by checking subscriptions
# To match the function in upstream get_operator_ns, we need to have such checks
# Parameters:
#   $1 - Optional operator name to search for (e.g., "sriov-network-operator")
# Returns: namespace if found, empty string otherwise
# Also sets APPLICATIONS_NS global variable based on which operator is found
function get_operator_ns() {
    local search_operator="$1"
    local operator_ns=""

    # If a specific operator is requested, search for it
    if [[ -n "${search_operator}" ]]; then
        operator_ns=$($KUBECTL get subscriptions -A -o jsonpath="{.items[?(@.spec.name=='${search_operator}')].metadata.namespace}" 2>/dev/null)
        if [[ -n "${operator_ns}" ]]; then
            echo "${operator_ns}"
            return
        fi

        # If not found via subscription, try finding by deployment label or name
        operator_ns=$($KUBECTL get deployments -A -l "app=${search_operator}" -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null)
        if [[ -n "${operator_ns}" ]]; then
            echo "${operator_ns}"
            return
        fi

        # Try finding by deployment name
        operator_ns=$($KUBECTL get deployments -A -o jsonpath="{.items[?(@.metadata.name=='${search_operator}')].metadata.namespace}" 2>/dev/null)
        if [[ -n "${operator_ns}" ]]; then
            echo "${operator_ns}"
            return
        fi

        echo ""
        return
    fi

    # No specific operator requested - check for default RHOAI/ODH operators
    # Check for rhods-operator subscription first
    operator_ns=$($KUBECTL get subscriptions -A -o jsonpath="{.items[?(@.spec.name=='rhods-operator')].metadata.namespace}" 2>/dev/null)
    if [[ -n "${operator_ns}" ]]; then
        APPLICATIONS_NS="${APPLICATIONS_NAMESPACE:-redhat-ods-applications}"
        echo "${operator_ns}"
        return
    fi

    # Check for opendatahub-operator subscription
    operator_ns=$($KUBECTL get subscriptions -A -o jsonpath="{.items[?(@.spec.name=='opendatahub-operator')].metadata.namespace}" 2>/dev/null)
    if [[ -n "${operator_ns}" ]]; then
        APPLICATIONS_NS="${APPLICATIONS_NAMESPACE:-opendatahub}"
        echo "${operator_ns}"
        return
    fi

    # Neither found
    echo ""
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

# Auto-discovery function for both namespaced and cluster-scoped resources
# Automatically discovers all available resources and collects only those that exist
function auto_discover_resources() {
    local namespaced="$1"
    local dest_dir="$2"
    local namespace="$3"   # only used if namespaced=true

    local scope_flag="--namespaced=${namespaced}"
    local ns_flag=""
    if [[ "$namespaced" == "true" ]]; then
        ns_flag="-n ${namespace}"
    fi

    # shellcheck disable=SC2086
    while IFS= read -r line; do
        local resource_name
        local api_version
        resource_name=$(echo "$line" | awk '{print $1}')
        api_version=$(echo "$line" | awk '{print $3}')
        [[ -z "$resource_name" ]] && continue # handle warning line

        # Check if any resources of this type exist
        if ! $KUBECTL get "$resource_name" $ns_flag --no-headers 2>/dev/null | grep -q .; then
            continue  # skip if not exist
        fi

        local api_group="${api_version%/*}"
        [[ "$api_version" != */* ]] && api_group="core" # core only show as v1
        local subdir="${api_group}"

        mkdir -p "${dest_dir}/${subdir}"

        # Special handling for events: transform 'kind: List' to 'kind: EventList'
        # This is needed for oc adm must-gather post-processing
        if [[ "$resource_name" == "events" ]]; then
            $KUBECTL get "$resource_name" $ns_flag -o yaml 2>/dev/null | \
                sed 's/^kind: List$/kind: EventList/' > "${dest_dir}/${subdir}/${resource_name}.yaml"
        else
            $KUBECTL get "$resource_name" $ns_flag -o yaml > "${dest_dir}/${subdir}/${resource_name}.yaml" 2>/dev/null
        fi
    done < <($KUBECTL api-resources $scope_flag --no-headers 2>/dev/null)
}

# Auto-discover and collect all cluster-scoped resources
function collect_cluster_scoped_resources() {
    local dest_dir="${DST_DIR}/cluster-scoped-resources"
    echo "Auto-discovering cluster-scoped resources..."
    auto_discover_resources "false" "${dest_dir}"
    echo "Cluster-scoped resources auto-discovery complete"
}
