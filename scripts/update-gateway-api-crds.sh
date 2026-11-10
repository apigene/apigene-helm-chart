#!/usr/bin/env bash
# Vendor the Gateway API standard-channel CRDs into the Terraform chart that installs
# them on EKS (terraform/modules/aws-load-balancer-controller/charts/gateway-api-crds).
#
#   ./scripts/update-gateway-api-crds.sh v1.6.1
#
# Match the version to what the AWS Load Balancer Controller release is built for
# (docs/guide/gateway/gateway.md in that release).

set -euo pipefail

VERSION="${1:?usage: $0 <gateway-api version, e.g. v1.6.1>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART="${SCRIPT_DIR}/../terraform/modules/aws-load-balancer-controller/charts/gateway-api-crds"
URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${VERSION}/standard-install.yaml"

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
curl -fsSL "${URL}" -o "${tmp}"

# Keep everything on helm uninstall: deleting a CRD deletes every Gateway and route in
# the cluster. The bundle holds the CRDs plus the safe-upgrades ValidatingAdmissionPolicy
# and its binding; each object has exactly one two-space-indented annotations block.
sed '/^  annotations:$/a\
    helm.sh/resource-policy: keep
' "${tmp}" > "${CHART}/files/standard-install.yaml"

objects="$(grep -c '^kind: ' "${CHART}/files/standard-install.yaml")"
crds="$(grep -c '^kind: CustomResourceDefinition$' "${CHART}/files/standard-install.yaml")"
kept="$(grep -c 'helm.sh/resource-policy: keep' "${CHART}/files/standard-install.yaml")"
[[ "${objects}" == "${kept}" ]] || { echo "error: ${objects} objects but ${kept} keep annotations" >&2; exit 1; }

sed -i.bak -E "s/^(version|appVersion): .*/\1: \"${VERSION#v}\"/" "${CHART}/Chart.yaml"
rm -f "${CHART}/Chart.yaml.bak"

echo "Vendored Gateway API ${VERSION} (${crds} CRDs) into ${CHART}"
