# upstream must-gather scripts
# Default: bd9f061 (2026-01-26) - can be overridden with --build-arg UPSTREAM_COMMIT=<commit>
FROM docker.io/alpine/git AS upstream
ARG UPSTREAM_COMMIT=bd9f06199d1e35685107d2df4a3f62b3bd62d2f8
RUN git clone https://github.com/openshift/must-gather.git /upstream && \
    cd /upstream && \
    git checkout ${UPSTREAM_COMMIT}

# vanilla k8s (kubectl-based) - UBI9 minimal
# quay.io/openshift/origin-cli:4.20 (larger, includes oc)
FROM registry.access.redhat.com/ubi9/ubi-minimal

# kubectl version (can be overridden with --build-arg KUBECTL_VERSION=vX.Y.Z)
ARG KUBECTL_VERSION=v1.31.4

# Install dependencies and kubectl (curl-minimal is pre-installed in ubi-minimal)
RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 jq tar gzip && \
    microdnf clean all && \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# Copy local collection scripts
COPY collection-scripts/ /usr/bin/k8s-gather/

# copy upstream infrastructure gather scripts
COPY --from=upstream \
    /upstream/collection-scripts/gather_istio \
    /upstream/collection-scripts/gather_metallb \
    /upstream/collection-scripts/gather_sriov \
    /usr/bin/k8s-gather/

# Patch upstream scripts: replace 'oc ' with 'kubectl ' (except 'oc adm inspect' which is handled by our wrapper)
# This fixes issues when scripts call 'oc get', 'oc exec', etc. with empty variables
RUN sed -i 's/\boc adm inspect\b/__OC_ADM_INSPECT__/g' /usr/bin/k8s-gather/gather_{istio,metallb,sriov} && \
    sed -i 's/\boc /kubectl /g' /usr/bin/k8s-gather/gather_{istio,metallb,sriov} && \
    sed -i 's/__OC_ADM_INSPECT__/oc adm inspect/g' /usr/bin/k8s-gather/gather_{istio,metallb,sriov}

# Patch gather_sriov: capture operator_ns output and exit gracefully if empty
RUN sed -i 's/^get_operator_ns "sriov-network-operator"$/operator_ns=$(get_operator_ns "sriov-network-operator"); if [[ -z "$operator_ns" ]]; then echo "INFO: SR-IOV operator not found, skipping"; exit 0; fi/' /usr/bin/k8s-gather/gather_sriov

RUN chmod -R +x /usr/bin/k8s-gather && \
    mkdir -p /must-gather && chmod 777 /must-gather && \
    ln -s /usr/bin/k8s-gather/oc /usr/local/bin/oc

WORKDIR /tmp

ENTRYPOINT ["/usr/bin/k8s-gather/gather"]
