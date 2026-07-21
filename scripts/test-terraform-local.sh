#!/usr/bin/env bash
# Test Terraform existing-cluster example against a local k3d cluster.
#
#   ./scripts/test-terraform-local.sh
#   TEARDOWN=1 ./scripts/test-terraform-local.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT}/terraform/examples/existing-cluster"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-apigene-tf-test}"
NAMESPACE="${APIGENE_NAMESPACE:-apigene}"
PORT="${APIGENE_PORT:-8080}"
TEARDOWN="${TEARDOWN:-0}"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: $1 is required" >&2; exit 1; }
}

require k3d
require kubectl
require terraform
require curl

if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME} "; then
  echo "Creating k3d cluster ${CLUSTER_NAME}..."
  k3d cluster create "${CLUSTER_NAME}" --agents 1 --k3s-arg "--disable=traefik@server:0" --wait
else
  echo "Using existing k3d cluster ${CLUSTER_NAME}"
  kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
fi

echo "Applying Terraform (existing-cluster example)..."
cd "${TF_DIR}"
terraform init -input=false
terraform apply -auto-approve \
  -var="tenant_name=local" \
  -var="fqdn=apigene.localtest" \
  -var="enable_tls=false" \
  -var="use_staging_issuer=true" \
  -var="aws_nlb=false" \
  -var="install_storage_class=false"

echo "Waiting for Apigene pods..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=apigene \
  -n "${NAMESPACE}" --timeout=600s

echo "Running smoke tests..."
kubectl port-forward -n "${NAMESPACE}" svc/nginx "${PORT}:8080" >/dev/null 2>&1 &
PF_PID=$!
sleep 3

cleanup() {
  kill "${PF_PID}" 2>/dev/null || true
}
trap cleanup EXIT

BASE_URL="http://localhost:${PORT}" "${ROOT}/scripts/smoke.sh"

echo "Local Terraform test completed successfully."

if [[ "${TEARDOWN}" == "1" ]]; then
  echo "Destroying Terraform resources..."
  terraform destroy -auto-approve \
    -var="tenant_name=local" \
    -var="fqdn=apigene.localtest" \
    -var="enable_tls=false" \
    -var="use_staging_issuer=true" \
    -var="aws_nlb=false" \
    -var="install_storage_class=false"
  echo "Deleting k3d cluster ${CLUSTER_NAME}..."
  k3d cluster delete "${CLUSTER_NAME}"
fi
