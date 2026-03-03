#!/bin/bash

set -e

NAMESPACE=${NAMESPACE:-k8s-gather}

usage() {
    cat <<EOF
Usage: $0 [create|delete]

Environment Variables:
  NAMESPACE              Namespace to use (default: k8s-gather)
  ENABLE_WVA             Enable workload-variant-autoscaler collection (default: false)
  ENABLE_MONITORING      Enable monitoring collection (default: false)
  AKS_MONITORING_TYPE    AKS monitoring type: managed or self-hosted (default: managed)

Examples:
  $0 create
  $0 delete
  NAMESPACE=my-gather $0 create
  ENABLE_WVA=true ENABLE_MONITORING=true $0 create
  ENABLE_MONITORING=true AKS_MONITORING_TYPE=self-hosted $0 create
EOF
    exit 1
}

create() {
    echo "Step 1: Creating RBAC resources..."

    # Check if env vars need to be overridden
    if [[ -n "${ENABLE_WVA:-}" ]] || [[ -n "${ENABLE_MONITORING:-}" ]] || [[ -n "${AKS_MONITORING_TYPE:-}" ]]; then
        # Create temporary overlay directory
        TEMP_DIR=$(mktemp -d)
        trap "rm -rf $TEMP_DIR" EXIT

        # Create kustomization that uses base and patches
        cat > "$TEMP_DIR/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $NAMESPACE

resources:
  - $(cd "$(dirname "$0")" && pwd)/manifests

patches:
  - patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/env
        value:
EOF

        # Build env array
        echo "          - name: ENABLE_WVA" >> "$TEMP_DIR/kustomization.yaml"
        echo "            value: \"${ENABLE_WVA:-false}\"" >> "$TEMP_DIR/kustomization.yaml"
        echo "          - name: ENABLE_MONITORING" >> "$TEMP_DIR/kustomization.yaml"
        echo "            value: \"${ENABLE_MONITORING:-false}\"" >> "$TEMP_DIR/kustomization.yaml"
        echo "          - name: AKS_MONITORING_TYPE" >> "$TEMP_DIR/kustomization.yaml"
        echo "            value: \"${AKS_MONITORING_TYPE:-managed}\"" >> "$TEMP_DIR/kustomization.yaml"

        cat >> "$TEMP_DIR/kustomization.yaml" <<EOF
    target:
      kind: Job
      name: k8s-gather
EOF
        # use patched kustozation.yaml
        kubectl apply -k "$TEMP_DIR"
    else
        kubectl apply -k deploy/manifests
    fi

    OUTPUT_DIR="./k8s-gather.local.$(date +%s)"
    
    sleep 10
    
    echo "Step 2: Getting pod name..."
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=k8s-gather -o jsonpath='{.items[0].metadata.name}')

    echo "Waiting for k8s-gather to complete..."
    until kubectl logs $POD_NAME -n $NAMESPACE 2>/dev/null | grep -q "DEBUG: Must-gather collection completed"; do
        sleep 20
    done
    echo "Collection completed!"

    echo "Step 3: Retrieving collected data to $OUTPUT_DIR..."
    kubectl cp $NAMESPACE/$POD_NAME:/must-gather $OUTPUT_DIR 2>/dev/null | grep -v "tar: Removing"

    echo "Done! Collected data is in: $OUTPUT_DIR"
    echo "To cleanup, run: $0 delete"
}

delete() {
    echo "Deleting k8s-gather resources..."
    kubectl delete -k deploy/manifests
    echo "Cleanup completed"
}

# Parse command
case "${1:-}" in
    create)
        create
        ;;
    delete)
        delete
        ;;
    *)
        usage
        ;;
esac
