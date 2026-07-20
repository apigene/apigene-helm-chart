#!/usr/bin/env bash
# Apigene Helm installer — upgrade --install wrapper with auth secret generation.
#
#   curl -fsSL https://raw.githubusercontent.com/apigene/apigene-helm-chart/main/scripts/install.sh | bash
#
# Environment variables:
#   APIGENE_RELEASE_NAME     Helm release name (default: apigene)
#   APIGENE_NAMESPACE        Kubernetes namespace (default: apigene)
#   APIGENE_AUTH_SECRET      Auth secret (generated if unset)
#   APIGENE_CHART_PATH       Path to chart (default: ./chart/apigene)
#   APIGENE_HELM_EXTRA_ARGS  Extra arguments passed to helm (e.g. -f values-production.yaml)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RELEASE_NAME="${APIGENE_RELEASE_NAME:-apigene}"
NAMESPACE="${APIGENE_NAMESPACE:-apigene}"
CHART_PATH="${APIGENE_CHART_PATH:-${REPO_ROOT}/chart/apigene}"
EXTRA_ARGS="${APIGENE_HELM_EXTRA_ARGS:-}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: $1 is required but not installed" >&2
    exit 1
  fi
}

require helm
require kubectl

if [[ -z "${APIGENE_AUTH_SECRET:-}" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    APIGENE_AUTH_SECRET="$(openssl rand -hex 32)"
    echo "Generated APIGENE_AUTH_SECRET (save this for upgrades): ${APIGENE_AUTH_SECRET}"
  else
    echo "error: set APIGENE_AUTH_SECRET or install openssl to generate one" >&2
    exit 1
  fi
fi

# shellcheck disable=SC2086
helm upgrade --install "${RELEASE_NAME}" "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set auth.secretKey="${APIGENE_AUTH_SECRET}" \
  ${EXTRA_ARGS}

echo ""
echo "Release ${RELEASE_NAME} installed in namespace ${NAMESPACE}."
echo "Watch pods: kubectl get pods -n ${NAMESPACE} -w"
echo "Smoke test: BASE_URL=http://localhost:8080 kubectl port-forward -n ${NAMESPACE} svc/nginx 8080:8080 &"
echo "            BASE_URL=http://localhost:8080 ${REPO_ROOT}/scripts/smoke.sh"
