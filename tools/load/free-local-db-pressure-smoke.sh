#!/usr/bin/env bash
set -euo pipefail

: "${TEST_DATABASE_URL:?TEST_DATABASE_URL is required}"
: "${RUNTIME_DATABASE_URL:?RUNTIME_DATABASE_URL is required}"

LOCAL_AUTH_TOKEN="${LOCAL_AUTH_TOKEN:-lifemate-local-pressure-token-001}"
LOCAL_AUTH_USER_ID="${LOCAL_AUTH_USER_ID:-33333333-3333-4333-8333-333333333333}"
AUTH_PORT="${AUTH_PORT:-19001}"
API_PORT="${API_PORT:-18001}"
OUTPUT_FILE="${OUTPUT_FILE:-db-pressure-fault-result.json}"

if [[ "$TEST_DATABASE_URL" != *"127.0.0.1"* && "$TEST_DATABASE_URL" != *"localhost"* ]]; then
  echo "TEST_DATABASE_URL must be local for the free DB-pressure smoke." >&2
  exit 2
fi
if [[ "$RUNTIME_DATABASE_URL" != *"127.0.0.1"* && "$RUNTIME_DATABASE_URL" != *"localhost"* ]]; then
  echo "RUNTIME_DATABASE_URL must be local for the free DB-pressure smoke." >&2
  exit 2
fi

command -v psql >/dev/null 2>&1 || { echo "psql is required." >&2; exit 2; }
command -v deno >/dev/null 2>&1 || { echo "deno is required." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 2; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
api_dir="$repo_root/supabase/functions/lifemate-api"
rm -f "$OUTPUT_FILE" runtime-pressure.ndjson runtime-pressure-status.json runtime-pressure-summary.json

cleanup() {
  for pid in "${collector_pid:-}" "${lock_pid:-}" "${api_pid:-}" "${auth_pid:-}"; do
    if [[ -n "$pid" ]]; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  for pid in "${collector_pid:-}" "${lock_pid:-}" "${api_pid:-}" "${auth_pid:-}"; do
    if [[ -n "$pid" ]]; then
      wait "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

LOCAL_AUTH_TOKEN="$LOCAL_AUTH_TOKEN" LOCAL_AUTH_USER_ID="$LOCAL_AUTH_USER_ID" AUTH_PORT="$AUTH_PORT" \
python3 - <<'PY' >/tmp/lifemate-pressure-auth.log 2>&1 &
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

token = os.environ['LOCAL_AUTH_TOKEN']
user_id = os.environ['LOCAL_AUTH_USER_ID']
port = int(os.environ['AUTH_PORT'])

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/auth/v1/user':
            self.send_response(404)
            self.end_headers()
            return
        if self.headers.get('Authorization') != f'Bearer {token}':
            body = b'{"message":"invalid synthetic session"}'
            self.send_response(401)
        else:
            body = json.dumps({
                'id': user_id,
                'email': 'local-pressure@example.invalid',
                'phone': None,
                'user_metadata': {'display_name': 'Local Pressure'},
                'identities': [],
            }).encode()
            self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        return

ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
PY
auth_pid=$!

auth_ready=0
for _ in $(seq 1 40); do
  if curl --silent --fail \
    --header "Authorization: Bearer $LOCAL_AUTH_TOKEN" \
    "http://127.0.0.1:$AUTH_PORT/auth/v1/user" \
    | jq -e --arg user "$LOCAL_AUTH_USER_ID" '.id == $user' >/dev/null 2>&1; then
    auth_ready=1
    break
  fi
  sleep 0.2
done
if [[ "$auth_ready" != '1' ]]; then
  echo "Local synthetic Auth did not become ready." >&2
  exit 1
fi

(
  cd "$api_dir"
  SUPABASE_DB_URL="$TEST_DATABASE_URL" \
  LIFEMATE_DB_URL="$RUNTIME_DATABASE_URL" \
  SUPABASE_URL="http://127.0.0.1:$AUTH_PORT" \
  SUPABASE_ANON_KEY='local-publishable-key' \
  SUPABASE_SERVICE_ROLE_KEY='local-service-role-placeholder-0123456789abcdef' \
  LIFEMATE_CONTACT_HASHING_SECRET='local-contact-hashing-secret-0123456789abcdef' \
  LIFEMATE_RELEASE_VERSION='free-local-db-pressure' \
  LIFEMATE_REQUIRE_TRANSACTION_POOLER='false' \
  LIFEMATE_RATE_LIMIT_MODE='local' \
  LIFEMATE_REQUIRE_DISTRIBUTED_RATE_LIMIT='false' \
  deno run --allow-env \
    --allow-net="127.0.0.1:5432,127.0.0.1:$AUTH_PORT,0.0.0.0:$API_PORT" \
    index.ts
) >/tmp/lifemate-pressure-api.log 2>&1 &
api_pid=$!

api_ready=0
for _ in $(seq 1 60); do
  if curl --silent --fail "http://127.0.0.1:$API_PORT/health" \
    | jq -e '.status == "ok" and .database == "ready" and .version == "free-local-db-pressure"' \
      >/dev/null 2>&1; then
    api_ready=1
    break
  fi
  sleep 1
done
if [[ "$api_ready" != '1' ]]; then
  echo "Local lifemate-api did not become ready." >&2
  tail -n 60 /tmp/lifemate-pressure-api.log || true
  exit 1
fi

bootstrap_body='{"displayName":"Local Pressure User","locale":"fa","timeZone":"Asia/Tehran"}'
bootstrap_status="$(curl --silent --show-error \
  --request POST \
  --output /tmp/pressure-bootstrap.json \
  --write-out '%{http_code}' \
  --header "Authorization: Bearer $LOCAL_AUTH_TOKEN" \
  --header 'Content-Type: application/json' \
  --header 'Idempotency-Key: 44444444-4444-4444-8444-444444444444' \
  --data "$bootstrap_body" \
  "http://127.0.0.1:$API_PORT/api/v1/users/bootstrap")"
if [[ "$bootstrap_status" != '200' ]] || \
   ! jq -e --arg auth "$LOCAL_AUTH_USER_ID" '.user.authSubject == $auth' \
     /tmp/pressure-bootstrap.json >/dev/null; then
  echo "Synthetic bootstrap failed with HTTP $bootstrap_status." >&2
  jq -c '{status,code,title}' /tmp/pressure-bootstrap.json 2>/dev/null || true
  exit 1
fi

LIFEMATE_OBSERVABILITY_TARGET=local \
DATABASE_URL="$TEST_DATABASE_URL" \
DURATION_SECONDS=12 \
INTERVAL_SECONDS=1 \
OUTPUT_FILE=runtime-pressure.ndjson \
STATUS_FILE=runtime-pressure-status.json \
bash "$repo_root/tools/load/collect-runtime-pressure.sh" &
collector_pid=$!

(
  psql "$TEST_DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 --tuples-only --no-align <<'SQL'
begin;
lock table lifemate.app_users in access exclusive mode;
select 'LIFEMATE_LOCK_ACQUIRED';
select pg_sleep(4);
commit;
SQL
) >/tmp/lifemate-db-lock.log 2>&1 &
lock_pid=$!

lock_ready=0
for _ in $(seq 1 40); do
  if grep -q 'LIFEMATE_LOCK_ACQUIRED' /tmp/lifemate-db-lock.log 2>/dev/null; then
    lock_ready=1
    break
  fi
  sleep 0.1
done
if [[ "$lock_ready" != '1' ]]; then
  echo "Could not establish the synthetic PostgreSQL lock." >&2
  cat /tmp/lifemate-db-lock.log >&2 || true
  exit 1
fi

fault_meta="$(curl --silent --show-error \
  --output /tmp/pressure-fault.json \
  --dump-header /tmp/pressure-fault.headers \
  --write-out '%{http_code} %{time_total}' \
  --header "Authorization: Bearer $LOCAL_AUTH_TOKEN" \
  "http://127.0.0.1:$API_PORT/api/v1/me")"
fault_status="${fault_meta%% *}"
fault_seconds="${fault_meta##* }"
retry_after="$(awk 'BEGIN{IGNORECASE=1} /^Retry-After:/ {gsub("\r", "", $2); print $2}' /tmp/pressure-fault.headers | tail -n 1)"

if [[ "$fault_status" != '503' ]] || \
   ! jq -e '.code == "database_busy" and .status == 503' /tmp/pressure-fault.json >/dev/null || \
   [[ "$retry_after" != '2' ]]; then
  echo "DB pressure was not converted to controlled database_busy 503 + Retry-After." >&2
  jq -c '{status,code,title}' /tmp/pressure-fault.json 2>/dev/null || true
  echo "retry_after=${retry_after:-missing}" >&2
  tail -n 30 /tmp/lifemate-pressure-api.log || true
  exit 1
fi

fault_ms="$(awk -v seconds="$fault_seconds" 'BEGIN { printf "%.0f", seconds * 1000 }')"
if (( fault_ms < 1500 || fault_ms > 4500 )); then
  echo "DB pressure response did not respect the bounded lock-timeout window: ${fault_ms}ms" >&2
  exit 1
fi

wait "$lock_pid"
lock_pid=''

recovery_status="$(curl --silent --show-error \
  --output /tmp/pressure-recovery.json \
  --write-out '%{http_code}' \
  --header "Authorization: Bearer $LOCAL_AUTH_TOKEN" \
  "http://127.0.0.1:$API_PORT/api/v1/me")"
if [[ "$recovery_status" != '200' ]] || \
   ! jq -e --arg auth "$LOCAL_AUTH_USER_ID" '.user.authSubject == $auth' \
     /tmp/pressure-recovery.json >/dev/null; then
  echo "API did not recover after the synthetic lock was released." >&2
  exit 1
fi

kill -TERM "$collector_pid" 2>/dev/null || true
set +e
wait "$collector_pid"
collector_exit=$?
set -e
collector_pid=''
if [[ "$collector_exit" != '0' ]]; then
  echo "Pressure collector failed during DB fault smoke." >&2
  exit 1
fi

node "$repo_root/tools/load/summarize-runtime-pressure.mjs" \
  runtime-pressure.ndjson runtime-pressure-summary.json
jq -e '.schemaVersion == "lifemate.runtime-pressure-collector.v1" and .exitCode == 0 and .samples >= 3' \
  runtime-pressure-status.json >/dev/null
jq -e '.schemaVersion == "lifemate.runtime-pressure.v1" and .samples >= 3 and .database.peakLifeMateRuntimeConnections >= 1 and .database.peakWaitingRuntimeConnections >= 1' \
  runtime-pressure-summary.json >/dev/null

jq -n \
  --argjson faultStatus "$fault_status" \
  --argjson faultDurationMs "$fault_ms" \
  --argjson retryAfterSeconds "$retry_after" \
  --argjson recoveryStatus "$recovery_status" \
  --argjson peakRuntimeConnections "$(jq '.database.peakLifeMateRuntimeConnections' runtime-pressure-summary.json)" \
  --argjson peakWaitingRuntimeConnections "$(jq '.database.peakWaitingRuntimeConnections' runtime-pressure-summary.json)" \
  '{
    schemaVersion:"lifemate.db-pressure-fault.v1",
    target:"local-disposable",
    fault:"postgres-lock-timeout",
    faultStatus:$faultStatus,
    faultDurationMs:$faultDurationMs,
    retryAfterSeconds:$retryAfterSeconds,
    recoveryStatus:$recoveryStatus,
    peakRuntimeConnections:$peakRuntimeConnections,
    peakWaitingRuntimeConnections:$peakWaitingRuntimeConnections
  }' > "$OUTPUT_FILE"

cat "$OUTPUT_FILE"
