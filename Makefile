IMG ?= quay.io/$(USER)/k8s-gather
IMG_VERSION ?= dev
IMAGE_BUILDER ?= podman

build:
	${IMAGE_BUILDER} build . -f Containerfile -t ${IMG}:${IMG_VERSION}

push:
	${IMAGE_BUILDER} push ${IMG}:${IMG_VERSION}

build-and-push: build push
