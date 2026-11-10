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
  local prod_url=(--set "publicUrl=https://apigene.example.com")
  local aws_args=(-f "${CHART}/values-production.yaml" -f "${CHART}/values-aws.yaml"
    --set "networkPolicy.ingressCidrs={10.0.0.0/16}")

  echo "==> Helm lint"
  helm lint "${CHART}" "${HELM_SET[@]}"
  helm lint "${CHART}" "${aws_args[@]}" "${prod_url[@]}" "${HELM_SET[@]}" "${prod_secrets[@]}"

  echo "==> Helm template (default values)"
  helm template apigene "${CHART}" -n apigene "${HELM_SET[@]}" > "${out}/default.yaml"

  echo "==> Helm template (production values: Gateway + cert-manager)"
  helm template apigene "${CHART}" -n apigene \
    -f "${CHART}/values-production.yaml" \
    "${prod_url[@]}" "${HELM_SET[@]}" "${prod_secrets[@]}" > "${out}/production.yaml"
  grep -q 'cert-manager.io/cluster-issuer: letsencrypt-prod' "${out}/production.yaml" \
    || { echo "production Gateway lacks the cert-manager annotation" >&2; exit 1; }
  grep -q 'name: apigene-tls' "${out}/production.yaml" \
    || { echo "production HTTPS listener lacks its certificateRef" >&2; exit 1; }

  echo "==> Helm template (production + AWS ALB values)"
  helm template apigene "${CHART}" -n apigene "${aws_args[@]}" "${prod_url[@]}" \
    "${HELM_SET[@]}" "${prod_secrets[@]}" > "${out}/aws.yaml"
  for kind in Gateway HTTPRoute LoadBalancerConfiguration TargetGroupConfiguration; do
    grep -q "^kind: ${kind}$" "${out}/aws.yaml" || { echo "AWS profile renders no ${kind}" >&2; exit 1; }
  done
  grep -q 'cert-manager.io' "${out}/aws.yaml" && { echo "AWS profile keeps the cert-manager annotation" >&2; exit 1; }
  grep -q 'certificateRefs' "${out}/aws.yaml" && { echo "AWS Gateway must not use certificateRefs (ACM)" >&2; exit 1; }

  echo "==> values-aws.yaml requires the VPC CIDR for the network policy"
  if helm template apigene "${CHART}" -n apigene -f "${CHART}/values-production.yaml" \
    -f "${CHART}/values-aws.yaml" "${prod_url[@]}" "${HELM_SET[@]}" "${prod_secrets[@]}" >/dev/null 2>&1; then
    echo "values-aws.yaml rendered without networkPolicy.ingressCidrs" >&2; exit 1
  fi

  echo "==> Helm template (Gateway attached to an existing Gateway)"
  helm template apigene "${CHART}" -n apigene "${prod_url[@]}" "${HELM_SET[@]}" \
    --set gateway.enabled=true --set gateway.create=false \
    --set-json 'gateway.parentRefs=[{"name":"shared","namespace":"gateway-system","sectionName":"https"}]' \
    > "${out}/gateway-attach.yaml"
  grep -q '^kind: Gateway$' "${out}/gateway-attach.yaml" && { echo "create=false still renders a Gateway" >&2; exit 1; }

  echo "==> No Ingress in any profile"
  grep -l '^kind: Ingress$' "${out}"/*.yaml && { echo "an Ingress was rendered" >&2; exit 1; }

  echo "==> Helm template (OpenShift values)"
  helm template apigene "${CHART}" -n apigene \
    -f "${CHART}/values-openshift.yaml" \
    "${HELM_SET[@]}" --set mongo.auth.password=ci-mongo > "${out}/openshift.yaml"
  # restricted-v2 assigns UIDs and fsGroups from the project range and rejects others.
  grep -E 'runAsUser|runAsGroup|fsGroup' "${out}/openshift.yaml" \
    && { echo "OpenShift profile sets fixed UIDs/GIDs" >&2; exit 1; }
  # A policy selecting every pod would isolate other workloads in a shared namespace.
  if grep -n 'podSelector: {}' "${out}/openshift.yaml"; then
    echo "a NetworkPolicy selects every pod in the namespace" >&2; exit 1
  fi

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
    # The CRDs catalog covers Gateway API; the AWS controller CRDs are checked on a
    # cluster (scripts/test-local-cluster.sh) instead.
    kubeconform -strict -summary -ignore-missing-schemas \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
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
