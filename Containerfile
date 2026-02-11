# upstream must-gather scripts
# SHA1: 63f5a0a (2024-01-23) - pin to specific commit for reproducibility
FROM docker.io/alpine/git AS upstream
RUN git clone --depth 1 https://github.com/openshift/must-gather.git /upstream

# vanilla k8s (kubectl-based) - UBI9 minimal
# quay.io/openshift/origin-cli:4.20 (larger, includes oc)
FROM registry.access.redhat.com/ubi9/ubi-minimal

# Install dependencies and kubectl (curl-minimal is pre-installed in ubi-minimal)
RUN microdnf install -y --nodocs --setopt=install_weak_deps=0 jq tar gzip && \
    microdnf clean all && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# Copy local collection scripts
COPY collection-scripts/common.sh /usr/bin/k8s-gather/
COPY collection-scripts/functions.sh /usr/bin/k8s-gather/
COPY collection-scripts/gather /usr/bin/k8s-gather/
COPY collection-scripts/oc /usr/bin/k8s-gather/
COPY collection-scripts/component/ /usr/bin/k8s-gather/component/
COPY collection-scripts/distro/ /usr/bin/k8s-gather/distro/
COPY collection-scripts/deps/ /usr/bin/k8s-gather/deps/

# copy upstream infrastructure gather scripts
COPY --from=upstream \
    /upstream/collection-scripts/gather_istio \
    /upstream/collection-scripts/gather_metallb \
    /upstream/collection-scripts/gather_sriov \
    /usr/bin/k8s-gather/

RUN chmod -R +x /usr/bin/k8s-gather && \
    mkdir -p /must-gather && chmod 777 /must-gather && \
    ln -s /usr/bin/k8s-gather/oc /usr/local/bin/oc

WORKDIR /tmp

ENTRYPOINT ["/usr/bin/k8s-gather/gather"]
