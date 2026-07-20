#!/usr/bin/env bash
# Create a local k3d cluster, deploy the chart, run tests, optionally tear down.
#
#   ./scripts/test-local-cluster.sh          # keep cluster after run
#   TEARDOWN=1 ./scripts/test-local-cluster.sh
#
# Requires: k3d, kubectl, helm, curl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-apigene-helm-test}"
NAMESPACE="${APIGENE_NAMESPACE:-apigene}"
PORT="${APIGENE_PORT:-8080}"
AUTH_SECRET="${APIGENE_AUTH_SECRET:-$(openssl rand -hex 32)}"
TEARDOWN="${TEARDOWN:-0}"
SKIP_TESTS="${SKIP_TESTS:-0}"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: $1 is required" >&2; exit 1; }
}

require k3d
require kubectl
require helm
require curl

if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME} "; then
  echo "Creating k3d cluster ${CLUSTER_NAME}..."
  k3d cluster create "${CLUSTER_NAME}" \
    --agents 1 \
    --wait
else
  echo "Using existing k3d cluster ${CLUSTER_NAME}"
  kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
fi

echo "Deploying Helm chart..."
echo "  (Pulling images + waiting for pods can take 5–15 min on first run.)"

# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

watch_deploy_progress "${NAMESPACE}" &
WATCH_PID=$!

helm upgrade --install apigene "${ROOT}/chart/apigene" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set auth.secretKey="${AUTH_SECRET}" \
  --wait --timeout 20m

stop_deploy_progress "${WATCH_PID}"

echo "Waiting for pods..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=apigene \
  -n "${NAMESPACE}" --timeout=600s

if [[ "${SKIP_TESTS}" == "1" ]]; then
  echo "SKIP_TESTS=1 — deployment ready, skipping test suite."
else
  echo "Running tests..."
  APIGENE_NAMESPACE="${NAMESPACE}" APIGENE_PORT="${PORT}" \
    BASE_URL="http://localhost:${PORT}" \
    "${ROOT}/scripts/run-tests.sh" --port-forward
fi

if [[ "${TEARDOWN}" == "1" ]]; then
  echo "Tearing down cluster ${CLUSTER_NAME}..."
  k3d cluster delete "${CLUSTER_NAME}"
fi

echo "Local cluster test completed successfully."
