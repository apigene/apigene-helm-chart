#!/usr/bin/env bash
# Smoke tests through the Gateway API path: Gateway → HTTPRoute → nginx → apps.
# Port-forwards the Envoy Gateway proxy Service, so it works on k3d without a load
# balancer. Expects a release installed with gateway.enabled=true (GATEWAY=1
# ./scripts/test-local-cluster.sh does that).
#
#   ./scripts/gateway-smoke.sh
#
# Environment:
#   APIGENE_NAMESPACE      default: apigene
#   APIGENE_RELEASE        Gateway name (release fullname), default: apigene
#   GATEWAY_HOST           Gateway hostname, default: apigene.localtest
#   ENVOY_NAMESPACE        default: envoy-gateway-system
#   GATEWAY_PORT           local port, default: 18081

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAMESPACE="${APIGENE_NAMESPACE:-apigene}"
RELEASE="${APIGENE_RELEASE:-apigene}"
HOST="${GATEWAY_HOST:-apigene.localtest}"
ENVOY_NAMESPACE="${ENVOY_NAMESPACE:-envoy-gateway-system}"
PORT="${GATEWAY_PORT:-18081}"
PF_PID=""
PF_LOG="${TMPDIR:-/tmp}/apigene-gateway-pf.log"

cleanup() {
  if [[ -n "${PF_PID}" ]]; then
    kill "${PF_PID}" 2>/dev/null || true
    wait "${PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "==> Gateway ${NAMESPACE}/${RELEASE} programmed, HTTPRoute accepted"
kubectl wait --for=condition=Programmed "gateway/${RELEASE}" -n "${NAMESPACE}" --timeout=300s
kubectl wait --for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True \
  "httproute/${RELEASE}" -n "${NAMESPACE}" --timeout=120s
kubectl wait --for=jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}'=True \
  "httproute/${RELEASE}" -n "${NAMESPACE}" --timeout=120s

svc="$(kubectl get svc -n "${ENVOY_NAMESPACE}" \
  -l "gateway.envoyproxy.io/owning-gateway-name=${RELEASE},gateway.envoyproxy.io/owning-gateway-namespace=${NAMESPACE}" \
  -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${svc}" ]] || { echo "error: no Envoy proxy Service for the Gateway" >&2; exit 1; }

echo "Port-forwarding ${ENVOY_NAMESPACE}/${svc}:80 → localhost:${PORT}..."
kubectl port-forward -n "${ENVOY_NAMESPACE}" "svc/${svc}" "${PORT}:80" >"${PF_LOG}" 2>&1 &
PF_PID=$!

for i in $(seq 1 60); do
  if curl -fsS -H "Host: ${HOST}" "http://localhost:${PORT}/nginx-health" >/dev/null 2>&1; then
    break
  fi
  if [[ "${i}" -eq 60 ]]; then
    echo "Gateway not answering; port-forward log:" >&2
    cat "${PF_LOG}" >&2 || true
    kubectl get gateway,httproute -n "${NAMESPACE}" -o wide >&2 || true
    exit 1
  fi
  sleep 2
done

echo ""
BASE_URL="http://localhost:${PORT}" HOST_HEADER="${HOST}" bash "${SCRIPT_DIR}/smoke.sh"

echo ""
echo "==> Other hostnames get no route"
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: other.invalid" "http://localhost:${PORT}/nginx-health")"
if [[ "${code}" != "404" ]]; then
  echo "  FAIL Host other.invalid → HTTP ${code}, expected 404" >&2
  exit 1
fi
echo "  OK   Host other.invalid → HTTP 404"

echo ""
echo "Gateway smoke tests passed."
