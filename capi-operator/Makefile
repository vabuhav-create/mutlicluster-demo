BUILD_CMD := kustomize build --enable-alpha-plugins --enable-exec --enable-helm .

.PHONY: build
build:
	$(BUILD_CMD)

.PHONY: apply
apply:
	$(BUILD_CMD) | kapp deploy -a capi-operator -y --apply-default-update-strategy=fallback-on-replace -f -
