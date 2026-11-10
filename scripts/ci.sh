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
  local out
  out="$(mktemp -d)"
  local prod_secrets=(--set "mongo.auth.password=ci-mongo" --set "redis.auth.password=ci-redis")

  echo "==> Helm lint"
  helm lint "${CHART}" "${HELM_SET[@]}"
  helm lint "${CHART}" -f "${CHART}/values-production.yaml" -f "${CHART}/values-aws.yaml" \
    "${HELM_SET[@]}" "${prod_secrets[@]}"

  echo "==> Helm template (default values)"
  helm template apigene "${CHART}" -n apigene "${HELM_SET[@]}" > "${out}/default.yaml"

  echo "==> Helm template (production values)"
  helm template apigene "${CHART}" -n apigene \
    -f "${CHART}/values-production.yaml" \
    "${HELM_SET[@]}" "${prod_secrets[@]}" > "${out}/production.yaml"

  echo "==> Helm template (production + AWS ALB values)"
  helm template apigene "${CHART}" -n apigene \
    -f "${CHART}/values-production.yaml" -f "${CHART}/values-aws.yaml" \
    --set publicUrl=https://apigene.example.com --set ingress.host=apigene.example.com \
    "${HELM_SET[@]}" "${prod_secrets[@]}" > "${out}/aws.yaml"

  echo "==> Helm template (OpenShift values)"
  helm template apigene "${CHART}" -n apigene \
    -f "${CHART}/values-openshift.yaml" \
    "${HELM_SET[@]}" --set mongo.auth.password=ci-mongo > "${out}/openshift.yaml"

  echo "==> Helm template (external MongoDB and Redis)"
  helm template apigene "${CHART}" -n apigene "${HELM_SET[@]}" \
    --set externalMongo.enabled=true --set externalMongo.url=mongodb://db:27017 \
    --set externalRedis.enabled=true --set externalRedis.host=cache --set externalRedis.port=6380 \
    > "${out}/external.yaml"
  grep -q 'value: "6380"' "${out}/external.yaml" || { echo "externalRedis.port not applied" >&2; exit 1; }

  echo "==> Resources follow the release namespace"
  helm template apigene "${CHART}" -n customer-ns "${HELM_SET[@]}" \
    | grep '^  namespace:' | grep -qv customer-ns && { echo "resource outside the release namespace" >&2; exit 1; }

  if command -v kubeconform >/dev/null 2>&1; then
    echo "==> kubeconform"
    kubeconform -strict -summary -ignore-missing-schemas \
      -kubernetes-version "${KUBE_VERSION:-1.34.0}" "${out}"/*.yaml
  else
    echo "(kubeconform not installed; skipping schema validation)"
  fi

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
