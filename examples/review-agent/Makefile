
KIND_CLUSTER=agent-sandbox

.PHONY: all
all: fix-go-generate lint-go build test-unit create-kind install-packages create-secrets install-review-system

.PHONY: fix-go-generate
fix-go-generate:
	../../dev/tools/fix-go-generate --working-dir ./repowatch

.PHONY: build
build:
	go build -o bin/manager repowatch/cmd/repowatch-controller/main.go

.PHONY: test-unit
test-unit:
	../../dev/tools/test-unit --working-dir ./repowatch

.PHONY: lint-go
lint-go:
	../../dev/tools/lint-go --working-dir ./repowatch

.PHONY: install-packages
install-packages:
	../../dev/tools/install-kro
	../../dev/tools/install-envoy

.PHONY: create-kind
create-kind:
	../../dev/tools/create-kind-cluster --recreate ${KIND_CLUSTER} --kubeconfig bin/KUBECONFIG

.PHONY: install-review-system
install-review-system:
	# Install Sandbox Operator 
	../../dev/tools/push-images --image-prefix=kind.local/ --kind-cluster-name=${KIND_CLUSTER}
	../../dev/tools/deploy-to-kube --image-prefix=kind.local/
	# Install RepoWatch Operator
	../../dev/tools/push-images --image-prefix=kind.local/ --kind-cluster-name=${KIND_CLUSTER} --working-dir ./repowatch
	../../dev/tools/deploy-to-kube --image-prefix=kind.local/ --working-dir ./repowatch
	# Install Review Application
	../../dev/tools/push-images --image-prefix=kind.local/ --kind-cluster-name=${KIND_CLUSTER} --working-dir ./review-ui
	../../dev/tools/push-images --image-prefix=kind.local/ --kind-cluster-name=${KIND_CLUSTER} --working-dir ./review-sidecar
	../../dev/tools/deploy-to-kube --image-prefix=kind.local/ --working-dir ./review-ui
	# Install Review RGD
	../../dev/tools/deploy-to-kube --image-prefix=kind.local/ --working-dir ./review-sandbox

.PHONY: create-secrets
create-secrets:
	kubectl create namespace review-agent-system || true
	@kubectl create secret -n review-agent-system generic gemini-vscode-tokens --from-literal=gemini=${GEMINI_API_KEY} || true
	@kubectl create secret -n review-agent-system generic github-pat --from-literal=pat=${GITHUB_PAT} || true

.PHONY: create-instance
create-instance:
	kubectl apply -f examples/review-sandbox.yaml
	sleep 5
	kubectl get reviewsandboxes
	sleep 5
	kubectl get pod devc-demo
	kubectl logs -f devc-demo

.PHONY: delete-instance
delete-instance:
	kubectl delete reviewsandbox demo

.PHONY: port-forward
port-forward:
	ENVOY_SERVICE=$$(kubectl get svc -n envoy-gateway-system --selector=gateway.envoyproxy.io/owning-gateway-namespace=review-agent-system,gateway.envoyproxy.io/owning-gateway-name=review-agent-gateway -o jsonpath='{.items[0].metadata.name}') && kubectl port-forward -n envoy-gateway-system --address 0.0.0.0 service/$${ENVOY_SERVICE} 13380:13380
	# kubectl port-forward -n review-agent-system --address 0.0.0.0 service/pr-review-ui 13380:80

.PHONY: redis-port-forward
redis-port-forward:
	kubectl port-forward -n review-agent-system --address 0.0.0.0 service/redis 6379:6379