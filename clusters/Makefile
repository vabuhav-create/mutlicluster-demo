BUILD_CMD := kustomize build --enable-alpha-plugins --enable-exec .

.PHONY: build
build:
	$(BUILD_CMD)

.PHONY: apply
apply: build
	$(BUILD_CMD) | kapp deploy -a test-workload-capi -y --apply-default-update-strategy=fallback-on-replace -f -

delete: 
	kapp delete -a test-workload-capi -y

.PHONY: managedcluster
managedcluster:
	kubectl apply -f ./managed-cluster.yaml
