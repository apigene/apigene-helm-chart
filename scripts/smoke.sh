#!/usr/bin/env bash
# Post-install health checks against the Apigene nginx entry point.
# Port-forward friendly: BASE_URL=http://localhost:8080 ./scripts/smoke.sh

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
BASE_URL="${BASE_URL%/}"

PASS=0
FAIL=0

pass() { echo "  OK   $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL $1" >&2; FAIL=$((FAIL + 1)); }

check_json() {
  local name="$1" path="$2" pattern="$3"
  local body code
  body="$(curl -fsS --max-time 30 "${BASE_URL}${path}" 2>/dev/null || true)"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${BASE_URL}${path}" 2>/dev/null || echo "?")"
  if echo "$body" | grep -qE "$pattern"; then
    pass "${name} (${path}) HTTP ${code}"
  else
    fail "${name} (${path}) HTTP ${code} — body: ${body:-<empty>}"
  fi
}

check_status() {
  local name="$1" path="$2" expected="$3"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${BASE_URL}${path}" 2>/dev/null || echo "?")"
  if [[ " ${expected} " == *" ${code} "* ]]; then
    pass "${name} (${path}) HTTP ${code}"
  else
    fail "${name} (${path}) HTTP ${code}, expected one of:${expected}"
  fi
}

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }

echo "Apigene smoke tests"
echo "Base URL: ${BASE_URL}"
echo ""

check_json "nginx health" "/nginx-health" '"service"[[:space:]]*:[[:space:]]*"nginx"'
check_json "backend health" "/api/health" '"status"[[:space:]]*:[[:space:]]*"ok"'
check_status "OpenAPI" "/openapi.json" "200 401 403"
check_status "API docs" "/docs" "200 401 403"
check_status "Copilot UI" "/" "200 301 302 307 308 404"

echo ""
echo "Passed: ${PASS}, Failed: ${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
