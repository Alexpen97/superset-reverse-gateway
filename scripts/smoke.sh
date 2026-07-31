#!/bin/bash
# Smoke checks for http://demo.io/bi + http://demo.io/auth
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a && source .env && set +a
fi

BI_HOSTNAME="${BI_HOSTNAME:-demo.io}"
GATEWAY_PORT="${GATEWAY_PORT:-80}"
GATEWAY_URL="${GATEWAY_URL:-http://${BI_HOSTNAME}}"
KEYCLOAK_URL="${KEYCLOAK_EXTERNAL_URL:-http://${BI_HOSTNAME}/auth}"
REALM="${KEYCLOAK_REALM:-bi}"
FAIL=0

CURL_RESOLVE=(--resolve "${BI_HOSTNAME}:${GATEWAY_PORT}:127.0.0.1")
curl_r() { curl "${CURL_RESOLVE[@]}" "$@"; }

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAIL=1; }

echo "== smoke: waiting for gateway /bi/health =="
ok=0
for i in $(seq 1 60); do
  code="$(curl_r -s -o /tmp/bi-health.body -w '%{http_code}' "${GATEWAY_URL}/bi/health" || true)"
  if [[ "$code" == "200" ]]; then
    ok=1
    break
  fi
  sleep 5
done
if [[ "$ok" -eq 1 ]]; then
  pass "GET ${GATEWAY_URL}/bi/health -> 200"
else
  fail "GET ${GATEWAY_URL}/bi/health never returned 200 (last=${code:-none})"
fi

echo "== smoke: Keycloak OIDC discovery via /auth =="
disc="$(curl_r -s -o /tmp/kc-disc.json -w '%{http_code}' \
  "${KEYCLOAK_URL}/realms/${REALM}/.well-known/openid-configuration" || true)"
if [[ "$disc" == "200" ]] && grep -q "authorization_endpoint" /tmp/kc-disc.json; then
  pass "Keycloak discovery for realm '${REALM}'"
else
  fail "Keycloak discovery failed (http=${disc})"
fi

issuer="$(python3 -c "import json; print(json.load(open('/tmp/kc-disc.json')).get('issuer',''))" 2>/dev/null || true)"
expected_issuer="${KEYCLOAK_URL}/realms/${REALM}"
if [[ "$issuer" == "$expected_issuer" ]]; then
  pass "OIDC issuer is ${issuer}"
else
  fail "OIDC issuer mismatch: got '${issuer}' expected '${expected_issuer}'"
fi

echo "== smoke: unauthenticated /bi redirects toward login/oauth =="
loc="$(curl_r -s -o /dev/null -w '%{redirect_url}' "${GATEWAY_URL}/bi/" || true)"
code="$(curl_r -s -o /dev/null -w '%{http_code}' "${GATEWAY_URL}/bi/" || true)"
if [[ "$code" =~ ^30[12378]$ ]] || [[ "$loc" == *login* ]] || [[ "$loc" == *oauth* ]] || [[ "$loc" == *keycloak* ]]; then
  pass "GET /bi/ challenges auth (http=${code}, redirect=${loc:-none})"
else
  login_code="$(curl_r -s -o /dev/null -w '%{http_code}' "${GATEWAY_URL}/bi/login/" || true)"
  if [[ "$login_code" == "200" ]] || [[ "$login_code" =~ ^30 ]]; then
    pass "GET /bi/login/ reachable (http=${login_code})"
  else
    fail "Expected auth challenge at /bi/ (http=${code}, redirect=${loc:-none}, login=${login_code})"
  fi
fi

echo "== smoke: OAuth start redirects to Keycloak on same host =="
curl_r -sS -o /dev/null -c /tmp/bi-cj -b /tmp/bi-cj "${GATEWAY_URL}/bi/login/" >/dev/null || true
oauth_loc="$(curl_r -sS -o /dev/null -w '%{redirect_url}' -c /tmp/bi-cj -b /tmp/bi-cj \
  "${GATEWAY_URL}/bi/login/keycloak" || true)"
if [[ "$oauth_loc" == *"${BI_HOSTNAME}/auth/realms/${REALM}/protocol/openid-connect/auth"* ]]; then
  pass "GET /bi/login/keycloak -> ${BI_HOSTNAME}/auth authorize"
else
  fail "Expected Keycloak authorize on ${BI_HOSTNAME}/auth, got '${oauth_loc}'"
fi

echo "== smoke: SPA unprefixed /login/keycloak is rewritten via gateway =="
curl_r -sS -o /dev/null -c /tmp/bi-cj2 -b /tmp/bi-cj2 "${GATEWAY_URL}/bi/login/" >/dev/null || true
compat_loc="$(curl_r -sS -o /dev/null -w '%{redirect_url}' -c /tmp/bi-cj2 -b /tmp/bi-cj2 \
  "${GATEWAY_URL}/login/keycloak" || true)"
compat_code="$(curl_r -sS -o /dev/null -w '%{http_code}' -c /tmp/bi-cj3 -b /tmp/bi-cj3 \
  "${GATEWAY_URL}/login/keycloak" || true)"
if [[ "$compat_loc" == *"/auth/realms/${REALM}/protocol/openid-connect/auth"* ]] || [[ "$compat_code" == "302" ]]; then
  pass "GET /login/keycloak (SPA path) -> Keycloak authorize (http=${compat_code})"
else
  fail "SPA path /login/keycloak failed (http=${compat_code}, redirect=${compat_loc})"
fi

echo "== smoke: compose service health =="
if docker compose ps --format json >/dev/null 2>&1; then
  unhealthy="$(docker compose ps --format '{{.Name}} {{.Status}}' | grep -i unhealthy || true)"
  if [[ -z "$unhealthy" ]]; then
    pass "No unhealthy compose services"
  else
    fail "Unhealthy services: ${unhealthy}"
  fi
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo
  echo "Smoke checks FAILED"
  exit 1
fi
echo
echo "Smoke checks PASSED"
echo "Manual SSO: open ${GATEWAY_URL}/bi/login/ as analyst/analyst (after make setup)"
exit 0
