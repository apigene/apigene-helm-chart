#!/usr/bin/env bash
# CI entrypoint — run all chart checks and end-to-end tests.
#
#   ./scripts/ci.sh          # chart + e2e (default)
#   ./scripts/ci.sh chart    # helm lint + template only
#   ./scripts/ci.sh e2e      # k3d deploy + smoke + integration
#
# Environment:
#   AUTH_SECRET             Helm auth.secretKey (default: test secret)
#   TEARDOWN                Delete k3d cluster after e2e (default: 1 in CI, 0 locally)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AUTH_SECRET="${AUTH_SECRET:-testsecret12345678901234567890123456789012}"
HELM_SET=(--set "auth.secretKey=${AUTH_SECRET}")
CHART="${ROOT}/chart/apigene"

run_chart_tests() {
  echo "==> Helm lint"
  helm lint "${CHART}" "${HELM_SET[@]}"

  echo "==> Helm template (default values)"
  helm template apigene "${CHART}" \
    -n apigene --create-namespace \
    "${HELM_SET[@]}" > /dev/null

  echo "==> Helm template (production values)"
  helm template apigene "${CHART}" \
    -n apigene --create-namespace \
    -f "${CHART}/values-production.yaml" \
    "${HELM_SET[@]}" > /dev/null

  echo "Chart tests passed."
}

run_e2e_tests() {
  echo "==> End-to-end tests (k3d + deploy + smoke + integration)"
  TEARDOWN="${TEARDOWN:-1}" "${ROOT}/scripts/test-local-cluster.sh"
}

mode="${1:-all}"

case "${mode}" in
  chart)
    run_chart_tests
    ;;
  e2e)
    run_e2e_tests
    ;;
  all)
    run_chart_tests
    run_e2e_tests
    ;;
  *)
    echo "usage: $0 [chart|e2e|all]" >&2
    exit 1
    ;;
esac

echo "CI completed successfully."
