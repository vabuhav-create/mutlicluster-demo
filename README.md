# KPP Tier-2: Multi-Cluster Kubernetes Platform

A proof-of-concept multi-cluster management platform that provisions and manages Kubernetes clusters on Akamai cloud using Cluster API (CAPI) with Open Cluster Management (OCM) and Sveltos for add-on distribution.

## Architecture Overview

```ini
                    ┌─────────────────────────────────────────────────────┐
                    │            MANAGEMENT CLUSTER (Hub)                 │
                    ├─────────────────────────────────────────────────────┤
                    │  CAPI Operator ─► Provisions workload clusters      │
                    │  OCM Hub       ─► Multi-cluster registration        │
                    │  Sveltos       ─► Add-on/policy distribution        │
                    └─────────────────────────┬───────────────────────────┘
                                              │
                         ┌────────────────────┼────────────────────┐
                         ▼                    ▼                    ▼
                ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
                │ WORKLOAD CLUSTER│  │ WORKLOAD CLUSTER│  │ WORKLOAD CLUSTER│
                ├─────────────────┤  ├─────────────────┤  ├─────────────────┤
                │ • Klusterlet    │  │ • Klusterlet    │  │ • Klusterlet    │
                └─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Prerequisites

- An LKE (Linode Kubernetes Engine) cluster for the management plane
- [direnv](https://direnv.net/) installed
- [devbox](https://www.jetify.com/devbox) installed (provides kubectl, helm, kustomize, clusterctl, etc.)
- Linode API token with full access

## Quick Start

### Setup Environment

#### Token

```bash {"category":"init","excludeFromRunAll":"true","name":"setup-env"}
# Copy and configure environment variables
cp .env.local.example .env.local
```

Edit .env.local with your values:

- LINODE_TOKEN: Your Linode API token

```bash {"category":"init","excludeFromRunAll":"true","name":"edit-env"}
# Allow direnv to load the environment
# This automatically:
# - Enters devbox shell (provides kubectl, helm, kustomize, clusterctl, etc.)
# - Loads .env.local variables
# - Fetches and configures KUBECONFIG for your LKE cluster
direnv allow
```

#### LKE Cluster

```bash {"category":"init","excludeFromRunAll":"true","name":"create-lke-cluster"}
linode-cli lke cluster-create \
  --label kpp-tier2-management \
  --region $LINODE_REGION \
  --k8s_version 1.34 \
  --node_pools.type g6-standard-2 \
  --node_pools.count 3 \
  --tags kpp-tier2,management \
  # --apl_enabled false \
  --control_plane.high_availability false 
```

#### Get kubeconfig

```sh {"category":"init","excludeFromRunAll":"true","name":"get-kubeconfig"}
cluster_id=$(linode-cli lke clusters-list --label kpp-tier2-management --json | jq -r '.[0].id // empty')
if [ -z "$cluster_id" ]; then
  echo "Error: Cluster not found" >&2
  exit 1
fi
linode-cli lke kubeconfig-view "$cluster_id" --json | jq -r '.[0].kubeconfig' | base64 -d > kubeconfig

kubectl cluster-info
```

> **Note**: The `.envrc` file automatically export the kubeconfig.

### CAPI Provider Setup

#### Install cert-manager

```sh {"name":"cert-manager-install"}
make cert-manager-install
```

#### Install CAPI Operator and Providers

```sh {"name":"capi-operator-install"}
make capi-operator-apply
```

This installs:

- CAPI Operator (manages provider lifecycle)
- CoreProvider (Cluster API v1.12.1)
- InfrastructureProvider (CAPL - Linode v0.10.0)
- BootstrapProvider & ControlPlaneProvider (kubeadm)
- AddonProvider (Helm charts via CAAPH v0.5.3)

> **Note**: If you encounter errors about namespaces not found, the CAPI Operator CRDs may not be ready yet. Wait a moment and re-run `make capi-operator-apply`.

Wait for all providers to be ready:

```sh {"name":"capi-check-providers"}
kubectl wait --for=condition=Ready coreproviders,infrastructureproviders,bootstrapproviders,controlplaneproviders,addonproviders -A --all --timeout=300s
```

### CAPI Cluster instanciation

```sh {"name":"capi-cluster-instantiate"}
echo "$SSH_AUTH_SOCK"
make clusters-apply
```

#### Verify Cluster Registration

```sh
kubectl get events -n test-workload-capi -w
```

```bash {"name":"verify-registration"}
# wait for the cluster to be ready
kubectl wait --for=condition=Available=True --timeout=15m cluster/test-workload --namespace=test-workload-capi
```

### OCM

#### Install Open Cluster Management (OCM)

```sh {"name":"ocm-init"}
make ocm
```

This installs the cluster-manager with feature gates:

- ClusterImporter (auto-imports CAPI clusters)
- ManagedClusterAutoApproval (auto-approves cluster registration)

> **Note**: Temporary RBAC fix may be needed:
>
> ```bash {"name":"install-ocm"}
> kubectl -n open-cluster-management get clusterrole cluster-manager -o json | jq '(.rules[] | select(.resources[]=="secrets") | select(.verbs[] | index("get"))).resourceNames |= (. + ["addon-webhook-serving-cert"] | unique)' | kubectl -n open-cluster-management apply -f -
> ```

Wait for the hub components to be running:

```bash {"name":"ocm-check-pods"}
kubectl -n open-cluster-management get pod
kubectl -n open-cluster-management-hub get pod
```

#### Install OCM Add-ons

```bash {"name":"ocm-install"}
make ocm-addons
```

This configures:

- cluster-proxy add-on (for accessing managed clusters)
- managed-serviceaccount add-on

### Sveltos

```bash {"name":"sveltos-install"}
make sveltos-install
```

```bash
kubectl create sa platform-admin
kubectl create clusterrolebinding platform-admin-access --clusterrole cluster-admin --serviceaccount default:platform-admin
```

### Sveltos-OCM

```bash {"name":"sveltos-ocm-install"}
make sveltos-ocm-install
```

### CAPI / OCM registration setup

```bash
make clusters-managedcluster
```

### Access Workload Cluster

```bash {"name":"access-workload-cluster"}
# Merge workload cluster kubeconfig into ./kubeconfig
clusterctl get kubeconfig test-workload -n test-workload-capi > ./kubeconfig-app
```

### Sveltos policies

```bash
make profiles-install
```

### Wiz

```bash {"name":"install-wiz"}
kustomize build ./wiz/ | kapp deploy -a wiz-profile -y --apply-default-update-strategy=fallback-on-replace  -f -
```

## Directory Structure

```ini
.
├── capi-operator/      # CAPI Operator and provider definitions
├── cert-manager/       # cert-manager installation
├── clusters/           # Workload cluster definitions
│   ├── test-workload.yaml    # Full cluster spec (CAPI + Helm charts)
│   ├── managed-cluster.yaml  # OCM ManagedCluster with CAPI annotation
│   ├── rbac.yaml             # RBAC for cluster importer
│   └── kustomization.yaml
├── ocm/                # OCM cluster-manager installation
├── ocm-addons/         # OCM add-ons (cluster-proxy, managed-serviceaccount)
├── profiles/           # Sveltos ClusterProfiles for add-ons
├── sveltos/            # Sveltos installation
├── sveltos-ocm/        # Sveltos-OCM integration
└── wiz/                # Wiz security profiles
```

## Key Components

### Cluster API (CAPI)

Declarative cluster lifecycle management:

- **LinodeCluster**: Defines the cluster infrastructure (VPC, NodeBalancer)
- **KubeadmControlPlane**: Control plane configuration
- **MachineDeployment**: Worker node pools
- **HelmChartProxy**: Deploys Helm charts to matching clusters

### Open Cluster Management (OCM)

Multi-cluster registration and workload distribution:

- **ManagedCluster**: Represents a registered cluster
- **Klusterlet**: Agent running on workload clusters
- **ManifestWork**: Deploy resources to managed clusters

The `cluster.x-k8s.io/cluster` annotation on ManagedCluster enables auto-import of CAPI clusters.

### Sveltos

Add-on and policy management:

- **ClusterProfile**: Defines add-ons to deploy based on cluster selectors
- Supports Helm charts, Kustomize, and raw YAML

## Makefile Targets

| Target                 | Description                              |
| ---------------------- | ---------------------------------------- |
| `cert-manager-install` | Install cert-manager                     |
| `capi-operator-apply`  | Install CAPI operator and providers      |
| `ocm`                  | Install OCM cluster-manager              |
| `ocm-addons`           | Install OCM add-ons (proxy, MSA)         |
| `sveltos-install`      | Install Sveltos                          |
| `sveltos-ocm-install`  | Install Sveltos-OCM integration          |
| `clusters-apply`       | Create workload clusters                 |
| `clusters-delete`      | Delete workload clusters                 |
| `clusters-managedcluster` | Register clusters with OCM            |
| `profiles-install`     | Deploy Sveltos cluster profiles          |

## Troubleshooting

### OCM Registration Issues

**Problem**: ManagedCluster shows `AVAILABLE: Unknown`

1. Check the ManagedCluster status:

```bash {"name":"debug-managedcluster"}
kubectl describe managedcluster test-workload
```

2. Verify the CAPI annotation points to correct namespace:

```yaml
annotations:
  cluster.x-k8s.io/cluster: test-workload-capi/test-workload
```

3. Ensure RBAC allows reading kubeconfig secret:

```bash {"name":"debug-rbac"}
kubectl get role,rolebinding -n test-workload-capi | grep cluster-manager
```

4. Check registration controller logs:

```bash {"name":"debug-registration-logs"}
kubectl logs -n open-cluster-management-hub \
  deployment/cluster-manager-registration-controller --tail=50
```

### CAPI Cluster Not Provisioning

1. Check cluster status:

```bash {"name":"debug-cluster-status"}
kubectl describe cluster test-workload -n test-workload-capi
```

2. Check machine status:

```bash {"name":"debug-machines"}
kubectl get machines -n test-workload-capi
```

3. Check CAPL controller logs:

```bash {"name":"debug-capl-logs"}
kubectl logs -n capl-system deployment/capl-controller-manager --tail=50
```

### Klusterlet Not Running

1. Access workload cluster and check pods:

```bash {"name":"debug-klusterlet-pods"}
KUBECONFIG=./kubeconfig-app kubectl get pods -n open-cluster-management-agent
```

2. Check klusterlet logs:

```bash {"name":"debug-klusterlet-logs"}
KUBECONFIG=./kubeconfig-app kubectl logs -n open-cluster-management-agent \
  deployment/klusterlet --tail=50
```

## References

- [Cluster API Documentation](https://cluster-api.sigs.k8s.io/)
- [CAPL (Cluster API Provider Linode)](https://linode.github.io/cluster-api-provider-linode/)
- [Open Cluster Management](https://open-cluster-management.io/)
- [OCM CAPI Integration](https://open-cluster-management.io/docs/scenarios/register-capi-cluster/)
- [Sveltos](https://projectsveltos.github.io/sveltos/)
