#!/usr/bin/env bash
# Full-stack integration tests for a Helm-deployed Apigene platform.
# Expects a reachable BASE_URL (default: http://localhost:8080).
#
#   kubectl port-forward -n apigene svc/nginx 8080:8080 &
#   BASE_URL=http://localhost:8080 ./tests/integration.sh
#
# Or use: ./scripts/run-tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/tests/lib.sh"

tests_init_colors

NAMESPACE="${APIGENE_NAMESPACE:-apigene}"
PORT="${APIGENE_PORT:-8080}"
BASE_URL="${BASE_URL:-http://localhost:${PORT}}"
BASE_URL="${BASE_URL%/}"

EMAIL="ci-$(date +%s)@example.com"
PASSWORD="CiTestPass!234"
ORG_NAME="ciorg$(date +%s | tail -c 8)"
TOKEN=""
API_NAME=""
MCP_NAME=""
AGENT_ID=""
AGENT_NAME="ci-ifconfig-agent"
CONTEXT_ID=""
SKILL_ID=""
MCP_SERVER_ID=""
CLONE_API_NAME="ifconfig-ci-clone"
MEMBER_EMAIL="member-$(date +%s)@example.com"
MEMBER_PASSWORD="MemberPass!234"
CONTEXT_TYPE_ID=""
INTERACTION_ID=""

PASS=0
FAIL=0
WARN=0
START_TS="$(date +%s)"

pass() { apigene_ok "$1"; PASS=$((PASS + 1)); }
fail() { apigene_err "$1"; FAIL=$((FAIL + 1)); }
warn() { apigene_warn "$1"; WARN=$((WARN + 1)); }
info() { apigene_info "$1"; }
section() { apigene_section "$1"; }

json_field() {
  local json="$1" field="$2"
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
path = sys.argv[2].split(".")
cur = data
for p in path:
    if isinstance(cur, dict) and p in cur:
        cur = cur[p]
    else:
        sys.exit(1)
if cur is None:
    sys.exit(1)
print(cur if not isinstance(cur, (dict, list)) else json.dumps(cur))
' "$json" "$field" 2>/dev/null
}

http_json() {
  local method="$1" url="$2"
  shift 2
  local body code
  body="$(curl -sS --max-time 30 -X "$method" -w $'\n__HTTP_CODE__:%{http_code}' "$@" "$url" 2>/dev/null || true)"
  code="$(echo "$body" | sed -n 's/^__HTTP_CODE__://p' | tail -1)"
  body="$(echo "$body" | sed '/^__HTTP_CODE__:/d')"
  HTTP_CODE="$code"
  HTTP_BODY="$body"
}

expect_status() {
  local name="$1" expected="$2"
  if [[ " $expected " == *" $HTTP_CODE "* ]]; then
    pass "$name — HTTP $HTTP_CODE"
    return 0
  fi
  fail "$name — HTTP ${HTTP_CODE:-?} (expected one of:$expected): ${HTTP_BODY:0:200}"
  return 1
}

# Upstream ifconfig.co is often Cloudflare-blocked from GitHub-hosted runners.
# Keep run_action HTTP 200 as the hard check; treat live IP content as best-effort.
assert_upstream_ip_optional() {
  local label="$1" body="$2"
  local ip status
  status="$(python3 -c '
import json,sys
msg=(json.loads(sys.argv[1]).get("message") or {})
print(msg.get("status_code",""))
' "$body" 2>/dev/null || true)"
  ip="$(python3 -c '
import json,sys
msg=(json.loads(sys.argv[1]).get("message") or {})
content=msg.get("response_content") if isinstance(msg,dict) else None
if isinstance(content,dict) and content.get("ip"):
    print(content["ip"]); raise SystemExit(0)
if isinstance(content,str):
    try:
        parsed=json.loads(content)
        if isinstance(parsed,dict) and parsed.get("ip"):
            print(parsed["ip"]); raise SystemExit(0)
    except Exception:
        pass
raise SystemExit(1)
' "$body" 2>/dev/null || true)"
  if [[ -n "$ip" ]]; then
    pass "${label} returned ip=${ip}"
  elif [[ "$status" == "403" ]] || echo "$body" | grep -qi 'Just a moment\|cloudflare\|cf-ray'; then
    warn "${label} upstream blocked (Cloudflare/403) — skipped live IP assert"
  else
    warn "${label} no ip in response (status=${status:-?}) — skipped live IP assert"
  fi
}

apigene_banner "Apigene Helm Integration Tests"
info "Base URL: ${C_BOLD}${BASE_URL}${C_RESET}"
info "Namespace: ${NAMESPACE}"
info "Org:      ${ORG_NAME}"
info "Email:    ${EMAIL}"

section "Kubernetes validation"
if command -v kubectl >/dev/null 2>&1; then
  pass "kubectl available"
  if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    pass "namespace ${NAMESPACE} exists"
  else
    fail "namespace ${NAMESPACE} not found"
  fi
  not_ready="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '{split($2,a,"/"); if (a[1]!=a[2]) c++} END{print c+0}')"
  total="$(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${total}" -gt 0 && "${not_ready}" -eq 0 ]]; then
    pass "all ${total} pods ready in ${NAMESPACE}"
  elif [[ "${total}" -gt 0 ]]; then
    fail "${not_ready}/${total} pods not ready in ${NAMESPACE}"
    kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '{split($2,a,"/"); if (a[1]!=a[2]) print}' | while read -r line; do
      warn "pod not ready: ${line}"
    done
  else
    fail "no pods found in namespace ${NAMESPACE}"
  fi
else
  warn "kubectl not available — skipping cluster checks"
fi

section "Public endpoints"
http_json GET "${BASE_URL}/nginx-health"
expect_status "nginx-health" "200" || true
if [[ "$HTTP_CODE" == "200" ]] && echo "$HTTP_BODY" | grep -q '"service"[[:space:]]*:[[:space:]]*"nginx"'; then
  pass "nginx-health body includes service=nginx"
else
  fail "nginx-health body unexpected: ${HTTP_BODY:0:200}"
fi

http_json GET "${BASE_URL}/api/health"
expect_status "api/health" "200" || true
if [[ "$HTTP_CODE" == "200" ]] && echo "$HTTP_BODY" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
  pass "api/health status=ok"
else
  fail "api/health body unexpected: ${HTTP_BODY:0:200}"
fi

http_json GET "${BASE_URL}/api/version"
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "api/version — HTTP 200"
  if echo "$HTTP_BODY" | grep -q 'backend_version'; then
    pass "api/version includes backend_version"
  else
    warn "api/version response missing backend_version: ${HTTP_BODY:0:200}"
  fi
else
  # Some builds may not expose /version; treat non-200 as soft unless 5xx
  if [[ "$HTTP_CODE" =~ ^5 ]]; then
    fail "api/version — HTTP $HTTP_CODE"
  else
    warn "api/version — HTTP ${HTTP_CODE:-?} (optional endpoint)"
  fi
fi

http_json GET "${BASE_URL}/openapi.json"
expect_status "openapi.json" "200 401 403" || true

http_json GET "${BASE_URL}/.well-known/oauth-authorization-server"
expect_status "MCP OAuth well-known" "200 404 401 403" || true

http_json GET "${BASE_URL}/agent/does-not-exist/mcp"
# mcp-gw answers JSON-RPC; without Accept: text/event-stream it returns 406
expect_status "MCP gateway route (missing agent)" "401 403 404 405 406 500" || true

http_json GET "${BASE_URL}/agent/does-not-exist/mcp" \
  -H "Accept: text/event-stream"
# Proves nginx → mcp-gw routing; session/auth errors are expected without a real agent
expect_status "MCP gateway SSE Accept" "200 400 401 403 404 405 500" || true

section "Auth — unauthorized"
http_json GET "${BASE_URL}/api/user/me" -H "Authorization: Bearer invalid-token"
expect_status "user/me rejects bad token" "401 403" || true

http_json GET "${BASE_URL}/api/agent/list" -H "Authorization: Bearer invalid-token"
expect_status "agent/list rejects bad token" "401 403" || true

section "Auth — signup & login"
http_json POST "${BASE_URL}/api/user/signup/" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"org_name\":\"${ORG_NAME}\"}"
if expect_status "user signup" "200"; then
  if echo "$HTTP_BODY" | grep -qi 'organization\|created\|success'; then
    pass "signup response indicates success"
  else
    warn "signup HTTP 200 but unexpected body: ${HTTP_BODY:0:200}"
  fi
fi

http_json POST "${BASE_URL}/api/user/signup/" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"org_name\":\"${ORG_NAME}\"}"
expect_status "duplicate signup rejected" "409 400" || true

http_json POST "${BASE_URL}/api/user/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${EMAIL}&password=${PASSWORD}"
if expect_status "user token" "200"; then
  TOKEN="$(json_field "$HTTP_BODY" "access_token" || true)"
  if [[ -n "$TOKEN" ]]; then
    pass "access_token returned"
  else
    fail "access_token missing from token response: ${HTTP_BODY:0:200}"
  fi
fi

http_json POST "${BASE_URL}/api/user/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${EMAIL}&password=WrongPassword!"
expect_status "bad password rejected" "401" || true

section "Authenticated API"
if [[ -z "$TOKEN" ]]; then
  fail "Skipping authenticated checks — no access token"
else
  http_json GET "${BASE_URL}/api/user/me" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "user/me" "200"; then
    me_email="$(json_field "$HTTP_BODY" "email" || true)"
    me_org="$(json_field "$HTTP_BODY" "org_name" || true)"
    [[ "$me_email" == "$EMAIL" ]] && pass "user/me email matches" || fail "user/me email='${me_email}' expected '${EMAIL}'"
    [[ "$me_org" == "$ORG_NAME" ]] && pass "user/me org_name matches" || fail "user/me org_name='${me_org}' expected '${ORG_NAME}'"
  fi

  http_json GET "${BASE_URL}/api/user/settings" -H "Authorization: Bearer ${TOKEN}"
  expect_status "user/settings" "200" || true

  http_json GET "${BASE_URL}/api/agent/list" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "agent/list" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d, list)' 2>/dev/null; then
      pass "agent/list returns a JSON array"
    else
      fail "agent/list body is not a JSON array: ${HTTP_BODY:0:200}"
    fi
  fi

  http_json GET "${BASE_URL}/api/mcp-server/list" -H "Authorization: Bearer ${TOKEN}"
  if [[ "$HTTP_CODE" == "200" ]]; then
    pass "mcp-server/list — HTTP 200"
  elif [[ "$HTTP_CODE" =~ ^(401|403|404)$ ]]; then
    warn "mcp-server/list — HTTP $HTTP_CODE (endpoint may differ by image version)"
  else
    fail "mcp-server/list — HTTP ${HTTP_CODE:-?}: ${HTTP_BODY:0:200}"
  fi
fi

section "Spec install + run_action (ifconfig)"
SPEC_FILE="${IFCONFIG_SPEC_PATH:-}"
if [[ -z "$SPEC_FILE" ]]; then
  if [[ -f "$ROOT/tests/fixtures/ifconfig.yaml" ]]; then
    SPEC_FILE="$ROOT/tests/fixtures/ifconfig.yaml"
  elif [[ -f "$ROOT/../apigene-openapi-spec/ifconfig.yaml" ]]; then
    SPEC_FILE="$ROOT/../apigene-openapi-spec/ifconfig.yaml"
  fi
fi

if [[ -z "$TOKEN" ]]; then
  fail "Skipping ifconfig flow — no access token"
elif [[ -z "$SPEC_FILE" || ! -f "$SPEC_FILE" ]]; then
  fail "ifconfig OpenAPI spec not found (set IFCONFIG_SPEC_PATH or add tests/fixtures/ifconfig.yaml)"
else
  info "Spec file: ${SPEC_FILE}"

  # Upload OpenAPI file and auto-create MCP server (create_mcp=true)
  UPLOAD_BODY="$(curl -sS --max-time 120 -X POST \
    -w $'\n__HTTP_CODE__:%{http_code}' \
    -H "Authorization: Bearer ${TOKEN}" \
    -F "file=@${SPEC_FILE};type=application/x-yaml;filename=ifconfig.yaml" \
    -F "global_spec=false" \
    -F "shared_security_info=false" \
    -F "create_mcp=true" \
    "${BASE_URL}/api/spec_from_file/" 2>/dev/null || true)"
  HTTP_CODE="$(echo "$UPLOAD_BODY" | sed -n 's/^__HTTP_CODE__://p' | tail -1)"
  HTTP_BODY="$(echo "$UPLOAD_BODY" | sed '/^__HTTP_CODE__:/d')"

  if expect_status "spec_from_file ifconfig.yaml" "200"; then
    API_NAME="$(json_field "$HTTP_BODY" "api_name" || true)"
    MCP_CREATED="$(json_field "$HTTP_BODY" "mcp_created" || true)"
    MCP_NAME="$(json_field "$HTTP_BODY" "mcp_info.name" || true)"
    [[ "$API_NAME" == "ifconfig" ]] && pass "installed api_name=ifconfig" || fail "api_name='${API_NAME}' expected ifconfig"
    [[ "$MCP_CREATED" == "True" || "$MCP_CREATED" == "true" ]] \
      && pass "MCP server auto-created for ifconfig" \
      || fail "mcp_created='${MCP_CREATED}' (expected true): ${HTTP_BODY:0:300}"
    [[ -n "$MCP_NAME" ]] && pass "MCP server name=${MCP_NAME}" || fail "mcp_info.name missing"
  else
    API_NAME="ifconfig"
    MCP_NAME="ifconfig"
  fi

  # run_action equivalent: POST /api/mcp/app_execute_action
  GENAI_APP="${MCP_NAME:-ifconfig}"
  http_json POST \
    "${BASE_URL}/api/mcp/app_execute_action?genai_app=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "${GENAI_APP}")&app_type=mcp" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"app_name\": \"${API_NAME:-ifconfig}\",
      \"user_input\": \"Get my public IP address\",
      \"context\": {
        \"operationId\": \"getMyIpInfo\",
        \"Accept\": \"application/json\"
      },
      \"response_format\": \"raw\"
    }"

  if expect_status "run_action getMyIpInfo (mcp)" "200"; then
    assert_upstream_ip_optional "getMyIpInfo (mcp)" "$HTTP_BODY"
  fi
fi

section "Spec APIs"
if [[ -z "$TOKEN" || -z "$API_NAME" ]]; then
  fail "Skipping spec API checks — missing token or api_name"
else
  http_json GET "${BASE_URL}/api/specs" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "specs list" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and any(x.get("api_name")==sys.argv[1] for x in d)' "$API_NAME" 2>/dev/null; then
      pass "specs list includes ${API_NAME}"
    else
      fail "specs list missing ${API_NAME}: ${HTTP_BODY:0:300}"
    fi
  fi

  http_json GET "${BASE_URL}/api/specs?include_all=true" -H "Authorization: Bearer ${TOKEN}"
  expect_status "specs list include_all" "200" || true

  http_json GET "${BASE_URL}/api/spec/${API_NAME}" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "spec get ${API_NAME}" "200"; then
    title="$(json_field "$HTTP_BODY" "api_title" || true)"
    [[ "$title" == "ifconfig" ]] && pass "spec api_title=ifconfig" || fail "spec api_title='${title}'"
  fi

  http_json GET "${BASE_URL}/api/spec/${API_NAME}/schema" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "spec schema" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "openapi" in d or "swagger" in d' 2>/dev/null; then
      pass "spec schema is OpenAPI document"
    else
      fail "spec schema unexpected: ${HTTP_BODY:0:200}"
    fi
  fi

  http_json GET "${BASE_URL}/api/spec/${API_NAME}/operations" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "spec operations" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; ops=json.load(sys.stdin).get("operations") or []; assert any(o.get("name")=="getMyIpInfo" for o in ops)' 2>/dev/null; then
      pass "operations include getMyIpInfo"
    else
      fail "operations missing getMyIpInfo: ${HTTP_BODY:0:300}"
    fi
  fi

  http_json GET "${BASE_URL}/api/spec/${API_NAME}/available_scopes" -H "Authorization: Bearer ${TOKEN}"
  expect_status "spec available_scopes" "200" || true

  http_json GET "${BASE_URL}/api/spec/${API_NAME}/agentic_metadata" -H "Authorization: Bearer ${TOKEN}"
  expect_status "spec agentic_metadata" "200" || true

  http_json POST "${BASE_URL}/api/spec/${API_NAME}/operation_schema" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '"getMyIpInfo"'
  if expect_status "spec operation_schema getMyIpInfo" "200"; then
    [[ "$(json_field "$HTTP_BODY" "operationId" || true)" == "getMyIpInfo" ]] \
      && pass "operation_schema operationId matches" \
      || fail "operation_schema unexpected: ${HTTP_BODY:0:300}"
  fi

  http_json POST "${BASE_URL}/api/spec/${API_NAME}/clone" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"clone_api_title\":\"${CLONE_API_NAME}\"}"
  if expect_status "spec clone" "200"; then
    cloned="$(json_field "$HTTP_BODY" "api_name" || true)"
    [[ "$cloned" == "$CLONE_API_NAME" ]] && pass "cloned api_name=${CLONE_API_NAME}" || fail "clone api_name='${cloned}'"
  fi

  http_json GET "${BASE_URL}/api/mcp-server/list" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "mcp-server list after install" "200"; then
    MCP_SERVER_ID="$(python3 -c '
import json,sys
name, api = sys.argv[1], sys.argv[2]
for x in json.load(sys.stdin):
    if x.get("name")==name or x.get("api_name")==api:
        print(x.get("id",""))
        break
' "${MCP_NAME:-ifconfig}" "$API_NAME" <<<"$HTTP_BODY" 2>/dev/null || true)"
    if [[ -n "$MCP_SERVER_ID" ]]; then
      pass "mcp-server id=${MCP_SERVER_ID}"
    else
      fail "mcp-server list missing ifconfig: ${HTTP_BODY:0:300}"
    fi
  fi

  if [[ -n "$MCP_SERVER_ID" ]]; then
    http_json GET "${BASE_URL}/api/mcp-server/get/${MCP_SERVER_ID}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "mcp-server get" "200" || true

    http_json PUT "${BASE_URL}/api/mcp-server/update/${MCP_SERVER_ID}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"enabled":true}'
    expect_status "mcp-server update" "200" || true
  fi
fi

section "Agent lifecycle + run_action"
if [[ -z "$TOKEN" || -z "$API_NAME" ]]; then
  fail "Skipping agent checks — missing token or api_name"
else
  http_json POST "${BASE_URL}/api/agent/create" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${AGENT_NAME}\",
      \"description\": \"CI agent for ifconfig\",
      \"instructions\": \"Help users look up their public IP.\",
      \"apis\": [\"${API_NAME}\"]
    }"
  if expect_status "agent create" "200"; then
    AGENT_ID="$(json_field "$HTTP_BODY" "id" || true)"
    [[ -n "$AGENT_ID" ]] && pass "agent id=${AGENT_ID}" || fail "agent create missing id"
  fi

  http_json POST "${BASE_URL}/api/agent/create" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${AGENT_NAME}\",
      \"description\": \"dup\",
      \"instructions\": \"dup\",
      \"apis\": [\"${API_NAME}\"]
    }"
  expect_status "duplicate agent rejected" "409" || true

  if [[ -n "$AGENT_ID" ]]; then
    http_json GET "${BASE_URL}/api/agent/get/${AGENT_ID}" -H "Authorization: Bearer ${TOKEN}"
    if expect_status "agent get by id" "200"; then
      [[ "$(json_field "$HTTP_BODY" "name" || true)" == "$AGENT_NAME" ]] \
        && pass "agent get name matches" \
        || fail "agent get name mismatch"
    fi
  fi

  http_json GET "${BASE_URL}/api/agent/get_by_name?name=${AGENT_NAME}" -H "Authorization: Bearer ${TOKEN}"
  expect_status "agent get_by_name" "200" || true

  if [[ -n "$AGENT_ID" ]]; then
    http_json PUT "${BASE_URL}/api/agent/update/${AGENT_ID}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"description":"CI agent updated"}'
    if expect_status "agent update" "200"; then
      [[ "$(json_field "$HTTP_BODY" "description" || true)" == "CI agent updated" ]] \
        && pass "agent description updated" \
        || fail "agent update description mismatch"
    fi
  fi

  http_json GET \
    "${BASE_URL}/api/mcp/get_instructions?genai_app=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "${AGENT_NAME}")&app_type=agent" \
    -H "Authorization: Bearer ${TOKEN}"
  if expect_status "mcp get_instructions (agent)" "200"; then
    if echo "$HTTP_BODY" | grep -qi 'instruction'; then
      pass "get_instructions returns instructions text"
    else
      fail "get_instructions unexpected: ${HTTP_BODY:0:200}"
    fi
  fi

  http_json GET \
    "${BASE_URL}/api/mcp/apps_search_actions?genai_app=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "${AGENT_NAME}")&app_type=agent&query=ip" \
    -H "Authorization: Bearer ${TOKEN}"
  expect_status "mcp apps_search_actions" "200" || true

  http_json POST \
    "${BASE_URL}/api/mcp/app_execute_action?genai_app=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "${AGENT_NAME}")&app_type=agent" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"app_name\": \"${API_NAME}\",
      \"user_input\": \"What is my public IP?\",
      \"context\": {
        \"operationId\": \"getMyIpInfo\",
        \"Accept\": \"application/json\"
      },
      \"response_format\": \"raw\"
    }"
  if expect_status "run_action getMyIpInfo (agent)" "200"; then
    assert_upstream_ip_optional "getMyIpInfo (agent)" "$HTTP_BODY"
  fi

  # Projection path still exercises Apigene; live projected fields depend on upstream.
  http_json POST \
    "${BASE_URL}/api/mcp/app_execute_action?genai_app=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "${MCP_NAME:-ifconfig}")&app_type=mcp" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"app_name\": \"${API_NAME}\",
      \"user_input\": \"Get IP with projection\",
      \"context\": {
        \"operationId\": \"getMyIpInfo\",
        \"Accept\": \"application/json\"
      },
      \"response_format\": \"raw\",
      \"response_projection\": \"{ip: ip, country: country}\"
    }"
  if expect_status "run_action with response_projection" "200"; then
    if echo "$HTTP_BODY" | python3 -c '
import json,sys
msg=json.load(sys.stdin).get("message") or {}
content=msg.get("response_content") if isinstance(msg,dict) else msg
assert isinstance(content,dict) and "ip" in content and "country" in content
' 2>/dev/null; then
      pass "response_projection returned ip+country"
    elif echo "$HTTP_BODY" | grep -qi 'Just a moment\|cloudflare\|"status_code":403'; then
      warn "response_projection upstream blocked (Cloudflare/403) — skipped field assert"
    else
      warn "response_projection no projected fields — skipped field assert"
    fi
  fi

  if [[ -n "$AGENT_ID" ]]; then
    http_json DELETE "${BASE_URL}/api/agent/delete/${AGENT_ID}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "agent delete" "200" || true
  fi
fi

section "Context CRUD"
if [[ -z "$TOKEN" ]]; then
  fail "Skipping context checks — no access token"
else
  http_json POST "${BASE_URL}/api/context" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "ci-context",
      "description": "Integration test context",
      "summary": "Used by CI",
      "when_to_use": "during integration tests"
    }'
  if expect_status "context create" "200"; then
    CONTEXT_ID="$(json_field "$HTTP_BODY" "id" || true)"
    [[ -n "$CONTEXT_ID" ]] && pass "context id=${CONTEXT_ID}" || fail "context create missing id"
  fi

  http_json GET "${BASE_URL}/api/context" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "context list" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and any(x.get("name")=="ci-context" for x in d)' 2>/dev/null; then
      pass "context list includes ci-context"
    else
      fail "context list missing ci-context: ${HTTP_BODY:0:300}"
    fi
  fi

  if [[ -n "$CONTEXT_ID" ]]; then
    http_json GET "${BASE_URL}/api/context/${CONTEXT_ID}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "context get" "200" || true
    http_json DELETE "${BASE_URL}/api/context/${CONTEXT_ID}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "context delete" "200" || true
  fi
fi

section "Skill CRUD"
if [[ -z "$TOKEN" ]]; then
  fail "Skipping skill checks — no access token"
else
  http_json POST "${BASE_URL}/api/skill" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "ci-skill",
      "description": "A skill for CI tests",
      "content": "---\nname: ci-skill\ndescription: A skill for CI tests\n---\n\n# CI Skill\n\nUse this during integration tests.\n"
    }'
  if expect_status "skill create" "200"; then
    SKILL_ID="$(json_field "$HTTP_BODY" "id" || true)"
    [[ -n "$SKILL_ID" ]] && pass "skill id=${SKILL_ID}" || fail "skill create missing id"
  fi

  http_json GET "${BASE_URL}/api/skill" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "skill list" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and any(x.get("name")=="ci-skill" for x in d)' 2>/dev/null; then
      pass "skill list includes ci-skill"
    else
      fail "skill list missing ci-skill: ${HTTP_BODY:0:300}"
    fi
  fi

  if [[ -n "$SKILL_ID" ]]; then
    http_json GET "${BASE_URL}/api/skill/${SKILL_ID}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "skill get" "200" || true
    http_json DELETE "${BASE_URL}/api/skill/${SKILL_ID}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "skill delete" "200" || true
  fi
fi

section "Settings, interactions, audit, org"
if [[ -z "$TOKEN" ]]; then
  fail "Skipping remaining API checks — no access token"
else
  http_json POST "${BASE_URL}/api/user/settings/update" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"dark_mode":"dark"}'
  expect_status "user settings update" "200" || true

  http_json GET "${BASE_URL}/api/user/settings" -H "Authorization: Bearer ${TOKEN}"
  expect_status "user settings get after update" "200" || true

  http_json POST "${BASE_URL}/api/interaction/list" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{}'
  if expect_status "interaction list" "200"; then
    COUNT="$(json_field "$HTTP_BODY" "count" || true)"
    INTERACTION_ID="$(python3 -c '
import json,sys
d=json.load(sys.stdin)
items=d.get("interactions") or []
print(items[0].get("_id","") if items else "")
' <<<"$HTTP_BODY" 2>/dev/null || true)"
    if [[ -n "$COUNT" && "$COUNT" -gt 0 ]]; then
      pass "interaction list count=${COUNT}"
    else
      fail "interaction list expected count>0: ${HTTP_BODY:0:300}"
    fi
  fi

  if [[ -n "$INTERACTION_ID" ]]; then
    http_json GET "${BASE_URL}/api/interaction/${INTERACTION_ID}" -H "Authorization: Bearer ${TOKEN}"
    if expect_status "interaction get" "200"; then
      [[ "$(json_field "$HTTP_BODY" "api_name" || true)" == "ifconfig" ]] \
        && pass "interaction get api_name=ifconfig" \
        || warn "interaction get api_name unexpected: ${HTTP_BODY:0:200}"
    fi
  fi

  http_json POST "${BASE_URL}/api/interaction/activity-timeline" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"hours":24,"bucket_minutes":60}'
  if expect_status "interaction activity-timeline" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "buckets" in d or "start" in d' 2>/dev/null; then
      pass "activity-timeline has timeline fields"
    else
      fail "activity-timeline unexpected: ${HTTP_BODY:0:200}"
    fi
  fi

  http_json GET "${BASE_URL}/api/audit/audit-logs" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "audit logs" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d.get("logs"), list)' 2>/dev/null; then
      pass "audit logs returns logs array"
    else
      fail "audit logs unexpected body: ${HTTP_BODY:0:300}"
    fi
  fi

  http_json GET "${BASE_URL}/api/audit/audit-logs?limit=5" -H "Authorization: Bearer ${TOKEN}"
  expect_status "audit logs with limit" "200" || true

  http_json GET "${BASE_URL}/api/audit/audit-logs/resource/agent/${AGENT_NAME}" -H "Authorization: Bearer ${TOKEN}"
  expect_status "audit resource history (agent)" "200" || true

  http_json GET "${BASE_URL}/api/org/settings" -H "Authorization: Bearer ${TOKEN}"
  expect_status "org settings" "200" || true

  http_json GET "${BASE_URL}/api/org/details/${ORG_NAME}" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "org details" "200"; then
    [[ "$(json_field "$HTTP_BODY" "name" || true)" == "$ORG_NAME" ]] \
      && pass "org details name matches" \
      || fail "org details name mismatch: ${HTTP_BODY:0:200}"
  fi

  http_json POST "${BASE_URL}/api/org/add_user/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
      \"email\": \"${MEMBER_EMAIL}\",
      \"password\": \"${MEMBER_PASSWORD}\",
      \"role\": \"User\",
      \"org_name\": \"${ORG_NAME}\"
    }"
  expect_status "org add_user" "200" || true

  http_json POST "${BASE_URL}/api/user/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${MEMBER_EMAIL}&password=${MEMBER_PASSWORD}"
  if expect_status "member login token" "200"; then
    MEMBER_TOKEN="$(json_field "$HTTP_BODY" "access_token" || true)"
    [[ -n "$MEMBER_TOKEN" ]] && pass "member access_token returned" || fail "member token missing"
  fi

  http_json DELETE "${BASE_URL}/api/org/remove_user/${MEMBER_EMAIL}" -H "Authorization: Bearer ${TOKEN}"
  expect_status "org remove_user" "200" || true
fi

section "Context-type CRUD"
if [[ -z "$TOKEN" ]]; then
  fail "Skipping context-type checks — no access token"
else
  http_json GET "${BASE_URL}/api/context-type" -H "Authorization: Bearer ${TOKEN}"
  expect_status "context-type list" "200" || true

  http_json GET "${BASE_URL}/api/context-type/defaults" -H "Authorization: Bearer ${TOKEN}"
  expect_status "context-type defaults" "200" || true

  http_json POST "${BASE_URL}/api/context-type" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "ci-context-type",
      "summary": "CI summary",
      "description": "CI description",
      "when_to_use": "during integration tests",
      "how_to_generate": "create from CI fixture"
    }'
  if expect_status "context-type create" "200"; then
    CONTEXT_TYPE_ID="$(json_field "$HTTP_BODY" "id" || true)"
    [[ -n "$CONTEXT_TYPE_ID" ]] && pass "context-type id=${CONTEXT_TYPE_ID}" || fail "context-type create missing id"
  fi

  if [[ -n "$CONTEXT_TYPE_ID" ]]; then
    http_json GET "${BASE_URL}/api/context-type/${CONTEXT_TYPE_ID}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "context-type get" "200" || true

    http_json PUT "${BASE_URL}/api/context-type/${CONTEXT_TYPE_ID}" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "ci-context-type",
        "summary": "updated",
        "description": "CI description",
        "when_to_use": "during integration tests",
        "how_to_generate": "create from CI fixture"
      }'
    expect_status "context-type update" "200" || true

    http_json DELETE "${BASE_URL}/api/context-type/${CONTEXT_TYPE_ID}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "context-type delete" "200" || true
  fi
fi

section "Catalog & system APIs"
if [[ -z "$TOKEN" ]]; then
  fail "Skipping catalog checks — no access token"
else
  http_json GET "${BASE_URL}/api/gpts/list" -H "Authorization: Bearer ${TOKEN}"
  expect_status "gpts list" "200" || true

  http_json GET "${BASE_URL}/api/gpts/explore" -H "Authorization: Bearer ${TOKEN}"
  expect_status "gpts explore" "200" || true

  http_json GET "${BASE_URL}/api/task" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "task list" "200"; then
    if echo "$HTTP_BODY" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)>=1' 2>/dev/null; then
      pass "task list is non-empty"
    else
      warn "task list empty or unexpected: ${HTTP_BODY:0:200}"
    fi
  fi

  http_json GET "${BASE_URL}/api/official-mcp-server" -H "Authorization: Bearer ${TOKEN}"
  expect_status "official-mcp-server list" "200" || true

  http_json GET "${BASE_URL}/api/ui-templates" -H "Authorization: Bearer ${TOKEN}"
  expect_status "ui-templates" "200" || true

  http_json GET "${BASE_URL}/api/generative-ui-templates/list" -H "Authorization: Bearer ${TOKEN}"
  expect_status "generative-ui-templates list" "200" || true

  http_json GET "${BASE_URL}/api/cache/keys" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "cache keys" "200"; then
    [[ "$(json_field "$HTTP_BODY" "status" || true)" == "success" ]] \
      && pass "cache keys status=success" \
      || fail "cache keys unexpected: ${HTTP_BODY:0:200}"
  fi

  http_json GET "${BASE_URL}/api/cache/key?key=ci-missing-key" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "cache key miss" "200"; then
    [[ "$(json_field "$HTTP_BODY" "status" || true)" == "not_found" ]] \
      && pass "cache key miss returns not_found" \
      || warn "cache key miss status unexpected: ${HTTP_BODY:0:200}"
  fi

  http_json POST "${BASE_URL}/api/cache_clear" -H "Authorization: Bearer ${TOKEN}"
  if expect_status "cache_clear" "200"; then
    [[ "$(json_field "$HTTP_BODY" "status" || true)" == "success" ]] \
      && pass "cache_clear status=success" \
      || fail "cache_clear unexpected: ${HTTP_BODY:0:200}"
  fi
fi

section "Spec cleanup"
if [[ -n "$TOKEN" ]]; then
  if [[ -n "$CLONE_API_NAME" ]]; then
    http_json DELETE "${BASE_URL}/api/spec/${CLONE_API_NAME}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "spec delete clone ${CLONE_API_NAME}" "200 404" || true
  fi
  if [[ -n "$API_NAME" ]]; then
    http_json DELETE "${BASE_URL}/api/spec/${API_NAME}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "spec delete ${API_NAME}" "200" || true

    http_json GET "${BASE_URL}/api/spec/${API_NAME}" -H "Authorization: Bearer ${TOKEN}"
    expect_status "spec get after delete" "404" || true
  fi
fi

section "Persistence round-trip"
if [[ -n "$TOKEN" ]]; then
  http_json GET "${BASE_URL}/api/user/me" -H "Authorization: Bearer ${TOKEN}"
  expect_status "user/me still valid after prior calls" "200" || true

  # Confirm Mongo still answers after API traffic (Kubernetes StatefulSet)
  if command -v kubectl >/dev/null 2>&1 \
    && kubectl exec -n "${NAMESPACE}" mongo-0 -- mongosh --quiet --eval 'db.runCommand({ ping: 1 }).ok' 2>/dev/null | grep -q 1; then
    pass "mongo still healthy after API traffic"
  else
    fail "mongo ping failed after API traffic"
  fi
fi

ELAPSED=$(( $(date +%s) - START_TS ))
echo ""
echo -e "${C_BOLD}━━ Integration summary ━━${C_RESET}"
echo -e "  ${C_GREEN}Passed:${C_RESET}  ${PASS}"
echo -e "  ${C_RED}Failed:${C_RESET}  ${FAIL}"
echo -e "  ${C_YELLOW}Warnings:${C_RESET} ${WARN}"
echo -e "  ${C_DIM}Duration: ${ELAPSED}s${C_RESET}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "${C_RED}${C_BOLD}✘ Integration tests failed.${C_RESET}"
  exit 1
fi

echo -e "${C_GREEN}${C_BOLD}✔ Integration tests passed.${C_RESET}"
exit 0
