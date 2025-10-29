.PHONY: all
all: fix-go-generate build lint-go test-unit

.PHONY: fix-go-generate
fix-go-generate:
	dev/tools/fix-go-generate

.PHONY: build
build:
	go build -o bin/manager cmd/agent-sandbox-controller/main.go

KIND_CLUSTER=agent-sandbox

.PHONY: deploy
deploy:
	./dev/tools/deploy-to-kube --image-prefix=kind.local/ $(if $(EXTENSIONS),--extensions)

.PHONY: deploy-kind
deploy-kind:
	./dev/tools/create-kind-cluster --recreate ${KIND_CLUSTER} --kubeconfig bin/KUBECONFIG
	./dev/tools/push-images --image-prefix=kind.local/ --kind-cluster-name=${KIND_CLUSTER}
	$(MAKE) deploy

.PHONY: delete-kind
delete-kind:
	kind delete cluster --name ${KIND_CLUSTER}

.PHONY: test-unit
test-unit:
	./dev/tools/test-unit

.PHONY: test-e2e
test-e2e:
	python3 ./dev/ci/presubmits/test-e2e

.PHONY: lint-go
lint-go:
	./dev/tools/lint-go
