IMG ?= quay.io/$(USER)/k8s-gather
IMG_VERSION ?= v1.2.0-rc1
IMAGE_BUILDER ?= podman
KUBECTL_VERSION ?= v1.31.4
UPSTREAM_COMMIT ?= bd9f06199d1e35685107d2df4a3f62b3bd62d2f8

HELM_CHART_PATH ?= deploy/helm/k8s-gather
HELM_REGISTRY ?= oci://quay.io/$(USER)/charts


# Build and Release
image-build:
	${IMAGE_BUILDER} build . -f Containerfile -t ${IMG}:${IMG_VERSION} --build-arg KUBECTL_VERSION=${KUBECTL_VERSION} --build-arg UPSTREAM_COMMIT=${UPSTREAM_COMMIT}

image-push: image-build
	${IMAGE_BUILDER} push ${IMG}:${IMG_VERSION}

helm-package:
	sed -i 's/^appVersion:.*/appVersion: "$(IMG_VERSION:v%=%)"/' ${HELM_CHART_PATH}/Chart.yaml
	sed -i 's/  tag:.*/  tag: $(IMG_VERSION)/' ${HELM_CHART_PATH}/values.yaml
	helm package ${HELM_CHART_PATH}

helm-push: helm-package
	helm push k8s-gather-*.tgz ${HELM_REGISTRY}
	rm -f k8s-gather-*.tgz

build-and-push: image-push helm-push


# Deployment settings
NAMESPACE ?= k8s-gather
RELEASE_NAME ?= k8s-gather
OUTPUT_DIR ?= ./my-k8s-gather-$(shell date +%Y%m%d-%H%M%S)
##@ Must-Gather Workflow
.PHONY: run-gather
run-gather: ## Run must-gather job (deletes existing job if present, then installs/upgrades)
	@echo "Deleting existing job if present..."
	@kubectl delete job $(RELEASE_NAME)-job -n $(NAMESPACE) --ignore-not-found=true
	@echo "Installing/upgrading Helm release..."
	helm upgrade --install $(RELEASE_NAME) $(HELM_CHART_PATH) \
		-n $(NAMESPACE) --create-namespace \
		--set image.repository=$(IMG) \
		--set image.tag=$(IMG_VERSION)

.PHONY: wait-gather
wait-gather: ## Wait for must-gather job to complete
	@echo "Waiting for job to complete (timeout: 10m)..."
	kubectl wait --for=condition=complete job/$(RELEASE_NAME)-job -n $(NAMESPACE) --timeout=10m

.PHONY: get-results
get-results: ## Copy results from must-gather pod
	@echo "Getting pod name..."
	$(eval POD := $(shell kubectl get pods -n $(NAMESPACE) -l job-name=$(RELEASE_NAME)-job -o jsonpath='{.items[0].metadata.name}'))
	@echo "Copying results from pod $(POD) to $(OUTPUT_DIR)..."
	kubectl cp $(NAMESPACE)/$(POD):/must-gather $(OUTPUT_DIR)
	@echo "Results saved to: $(OUTPUT_DIR)"

.PHONY: cleanup-gather
cleanup-gather: ## Cleanup must-gather resources (uninstall Helm release and delete namespace)
	@echo "Uninstalling Helm release..."
	helm uninstall $(RELEASE_NAME) -n $(NAMESPACE) --ignore-not-found
	@echo "Deleting namespace..."
	kubectl delete namespace $(NAMESPACE) --ignore-not-found=true

.PHONY: gather-all
gather-all: run-gather wait-gather get-results ## Complete workflow: run, wait, and get results
	@echo "Must-gather complete! Results in: $(OUTPUT_DIR)"