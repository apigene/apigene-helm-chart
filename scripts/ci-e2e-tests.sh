#!/usr/bin/env bash
# Port-forward nginx and run smoke + integration tests in one process tree.
# Required for CI: background jobs do not survive across GitHub Actions steps.
#
#   ./scripts/ci-e2e-tests.sh
#
# Environment:
#   APIGENE_NAMESPACE   default: apigene
#   APIGENE_PORT        local port (default: 18080)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="${APIGENE_NAMESPACE:-apigene}"
PORT="${APIGENE_PORT:-18080}"
PF_PID=""
PF_LOG="${TMPDIR:-/tmp}/apigene-pf.log"

cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: $1 is required" >&2; exit 1; }
}

require kubectl
require curl

echo "Port-forwarding svc/nginx in ${NAMESPACE} → localhost:${PORT}..."
kubectl port-forward -n "${NAMESPACE}" "svc/nginx" "${PORT}:8080" >"${PF_LOG}" 2>&1 &
PF_PID=$!

echo "Waiting for nginx at http://localhost:${PORT}/nginx-health ..."
for i in $(seq 1 60); do
  if curl -fsS "http://localhost:${PORT}/nginx-health" >/dev/null 2>&1; then
    echo "nginx reachable (attempt ${i})"
    break
  fi
  if [[ "${i}" -eq 60 ]]; then
    echo "port-forward log:" >&2
    cat "${PF_LOG}" >&2 || true
    kubectl get pods,svc -n "${NAMESPACE}" >&2 || true
    exit 1
  fi
  sleep 2
done

export BASE_URL="http://localhost:${PORT}"
export APIGENE_NAMESPACE="${NAMESPACE}"
export APIGENE_PORT="${PORT}"

echo ""
echo "==> Smoke tests"
bash "${ROOT}/scripts/smoke.sh"

echo ""
echo "==> Integration tests"
bash "${ROOT}/tests/integration.sh"

echo ""
echo "All e2e tests passed."
