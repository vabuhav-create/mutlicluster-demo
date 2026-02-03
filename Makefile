export KUBECONFIG

# Cert-manager
cert-manager-install:
	kustomize build --enable-helm ./cert-manager/ | kapp deploy -a cert-manager -y --apply-default-update-strategy=fallback-on-replace  -f -

# CAPI Operator
capi-operator-build:
	$(MAKE) -C capi-operator build
capi-operator-apply:
	$(MAKE) -C capi-operator apply

.PHONY: ocm
ocm:
	kustomize build --enable-helm ./ocm/ | kapp deploy -a ocm -y --apply-default-update-strategy=fallback-on-replace  -f -

# Clusters
clusters-build:
	$(MAKE) -C clusters build
clusters-apply:
	$(MAKE) -C clusters apply
clusters-delete:
	$(MAKE) -C clusters delete
clusters-managedcluster:
	$(MAKE) -C clusters managedcluster

# Sveltos
sveltos-install:
	kustomize build --enable-helm ./sveltos/ | kapp deploy -a sveltos -y --apply-default-update-strategy=fallback-on-replace  -f -

# OCM
.PHONY: ocm-addons
ocm-addons:
	kustomize build --enable-helm ./ocm-addons/ | kapp deploy -a ocm-addons -y --apply-default-update-strategy=fallback-on-replace  -f -

# Sveltos-OCM Integration
sveltos-ocm-install:
	kustomize build ./sveltos-ocm/ | kapp deploy -a sveltos-ocm -y --apply-default-update-strategy=fallback-on-replace  -f -
	@echo "Applying SveltosOCMCluster configuration..."
	kubectl apply -f ./sveltos-ocm/sveltos-ocm-cluster.yaml

profiles-install:
	kustomize build ./profiles/ | kapp deploy -a sveltos-profiles -y --apply-default-update-strategy=fallback-on-replace  -f -
