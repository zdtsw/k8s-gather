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
        local ns_dir="${dest_dir}/namespaces/${namespace}"
        mkdir -p "${ns_dir}/pods" "${ns_dir}/core" "${ns_dir}/apps" "${ns_dir}/events"

        # Get namespace yaml
        $KUBECTL get namespace "$namespace" -o yaml > "${ns_dir}/${namespace}.yaml" 2>/dev/null

        # Define resource which should be common for all distro
        declare -A resource_map=(
            ["all"]="core"
            ["configmaps"]="core"
            ["secrets"]="core"
            ["services"]="core"
            ["endpoints"]="core"
            ["persistentvolumeclaims"]="core"
            ["roles"]="core"
            ["rolebindings"]="core"
            ["serviceaccounts"]="core"
            ["networkpolicies"]="core"
            ["deployments"]="apps"
            ["statefulsets"]="apps"
            ["daemonsets"]="apps"
            ["replicasets"]="apps"
            ["jobs"]="apps"
            ["cronjobs"]="apps"
            ["events"]="events"
        )

        # Collect all standard resources
        for resource_type in "${!resource_map[@]}"; do
            local subdir="${resource_map[$resource_type]}"
            $KUBECTL get "$resource_type" -n "$namespace" -o yaml > "${ns_dir}/${subdir}/${resource_type}.yaml" 2>/dev/null
        done

        # Only collect routes on OpenShift
        if [[ "${K8S_DISTRO}" == "ocp" ]]; then
            $KUBECTL get routes -n "$namespace" -o yaml > "${ns_dir}/core/routes.yaml" 2>/dev/null
        fi

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

    echo "RHAII version: $version"
}

function get_operator_resource() {
    for k in $@; do
        # Check if resource type exists first
        if $KUBECTL api-resources --no-headers 2>/dev/null | grep -qw "${k%%.*}"; then
            kubectl_inspect "$k" || echo "Warning collecting $k"
        fi
    done
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
