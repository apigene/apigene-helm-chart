#!/usr/bin/env bash
# Run smoke + integration tests against a deployed Helm release.
#
# Usage:
#   ./scripts/run-tests.sh                          # assumes nginx reachable at :8080
#   ./scripts/run-tests.sh --port-forward           # auto port-forward to svc/nginx
#   APIGENE_NAMESPACE=staging ./scripts/run-tests.sh --port-forward
#
# Environment:
#   BASE_URL              Public URL (default: http://localhost:8080)
#   APIGENE_NAMESPACE     Kubernetes namespace (default: apigene)
#   APIGENE_PORT          Local port for port-forward (default: 8080)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="${APIGENE_NAMESPACE:-apigene}"
PORT="${APIGENE_PORT:-8080}"
BASE_URL="${BASE_URL:-http://localhost:${PORT}}"
PORT_FORWARD=0
PF_PID=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit 0
}

cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port-forward|-p) PORT_FORWARD=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: $1 is required" >&2; exit 1; }
}

require curl

if [[ "${PORT_FORWARD}" -eq 1 ]]; then
  require kubectl
  echo "Port-forwarding svc/nginx in ${NAMESPACE} → localhost:${PORT}..."
  kubectl port-forward -n "${NAMESPACE}" "svc/nginx" "${PORT}:${PORT}" >/tmp/apigene-test-pf.log 2>&1 &
  PF_PID=$!
  sleep 2
fi

export BASE_URL="${BASE_URL%/}"

echo "==> Smoke tests"
bash "${ROOT}/scripts/smoke.sh"

echo ""
echo "==> Integration tests"
bash "${ROOT}/tests/integration.sh"

echo ""
echo "All tests passed."
