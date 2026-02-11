IMG ?= quay.io/$(USER)/k8s-gather
IMG_VERSION ?= v1.0.0
IMAGE_BUILDER ?= podman
KUBECTL_VERSION ?= v1.31.4
UPSTREAM_COMMIT ?= bd9f06199d1e35685107d2df4a3f62b3bd62d2f8

HELM_CHART_PATH ?= deploy/helm/k8s-gather
HELM_REGISTRY ?= oci://quay.io/$(USER)/charts

image-build:
	${IMAGE_BUILDER} build . -f Containerfile -t ${IMG}:${IMG_VERSION} --build-arg KUBECTL_VERSION=${KUBECTL_VERSION} --build-arg UPSTREAM_COMMIT=${UPSTREAM_COMMIT}

image-push: image-build
	${IMAGE_BUILDER} push ${IMG}:${IMG_VERSION}

helm-package:
	helm package ${HELM_CHART_PATH}

helm-push: helm-package
	helm push k8s-gather-*.tgz ${HELM_REGISTRY}
	rm -f k8s-gather-*.tgz

build-and-push: image-build image-push helm-package helm-push