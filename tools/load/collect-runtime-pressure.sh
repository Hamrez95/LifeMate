#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"

INTERVAL_SECONDS="${INTERVAL_SECONDS:-5}"
DURATION_SECONDS="${DURATION_SECONDS:-120}"
OUTPUT_FILE="${OUTPUT_FILE:-runtime-pressure.ndjson}"
STATUS_FILE="${STATUS_FILE:-runtime-pressure-status.json}"
TARGET="${LIFEMATE_OBSERVABILITY_TARGET:-local}"
TARGET_PROJECT_REF="${TARGET_PROJECT_REF:-}"
PRODUCTION_PROJECT_REF="bwdvmniywyyijjauipnh"

if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || (( INTERVAL_SECONDS < 1 || INTERVAL_SECONDS > 60 )); then
  echo "INTERVAL_SECONDS must be an integer between 1 and 60." >&2
  exit 2
fi
if ! [[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]] || (( DURATION_SECONDS < 5 || DURATION_SECONDS > 7200 )); then
  echo "DURATION_SECONDS must be an integer between 5 and 7200." >&2
  exit 2
fi

case "$TARGET" in
  local)
    if [[ "$DATABASE_URL" != *"localhost"* && "$DATABASE_URL" != *"127.0.0.1"* ]]; then
      echo "Remote database sampling requires LIFEMATE_OBSERVABILITY_TARGET=staging." >&2
      exit 2
    fi
    ;;
  staging)
    if [[ -z "$TARGET_PROJECT_REF" ]]; then
      echo "TARGET_PROJECT_REF is required for staging runtime sampling." >&2
      exit 2
    fi
    if [[ "$TARGET_PROJECT_REF" == "$PRODUCTION_PROJECT_REF" ]]; then
      echo "Production project ref is explicitly blocked from load-test sampling." >&2
      exit 2
    fi
    if [[ "$DATABASE_URL" == *"$PRODUCTION_PROJECT_REF"* ]]; then
      echo "Production database URL is explicitly blocked from load-test sampling." >&2
      exit 2
    fi
    if [[ "$DATABASE_URL" != *"$TARGET_PROJECT_REF"* ]]; then
      echo "DATABASE_URL does not belong to TARGET_PROJECT_REF." >&2
      exit 2
    fi
    ;;
  *)
    echo "LIFEMATE_OBSERVABILITY_TARGET must be local or staging. Production is intentionally unsupported." >&2
    exit 2
    ;;
esac

command -v psql >/dev/null 2>&1 || {
  echo "psql is required." >&2
  exit 2
}

query_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/runtime-pressure.sql"
: > "$OUTPUT_FILE"
: > "$STATUS_FILE"

started_at=$SECONDS
started_epoch="$(date +%s)"
samples=0
stop_requested=0
collector_exit=0

on_term() {
  stop_requested=1
}

write_status() {
  local exit_code="$1"
  local ended_epoch coverage interrupted
  ended_epoch="$(date +%s)"
  coverage=$((SECONDS - started_at))
  if (( stop_requested == 1 )); then
    interrupted=true
  else
    interrupted=false
  fi
  printf '{"schemaVersion":"lifemate.runtime-pressure-collector.v1","target":"%s","startedAtEpoch":%d,"endedAtEpoch":%d,"coverageSeconds":%d,"requestedDurationSeconds":%d,"intervalSeconds":%d,"samples":%d,"interrupted":%s,"exitCode":%d}\n' \
    "$TARGET" "$started_epoch" "$ended_epoch" "$coverage" "$DURATION_SECONDS" \
    "$INTERVAL_SECONDS" "$samples" "$interrupted" "$exit_code" > "$STATUS_FILE"
}

on_exit() {
  local code="$?"
  if (( collector_exit != 0 && code == 0 )); then
    code="$collector_exit"
  fi
  write_status "$code"
}

trap on_term TERM INT
trap on_exit EXIT

while (( SECONDS - started_at < DURATION_SECONDS )); do
  if (( stop_requested == 1 )); then
    break
  fi
  if ! psql "$DATABASE_URL" \
    --no-psqlrc \
    --tuples-only \
    --no-align \
    --set=ON_ERROR_STOP=1 \
    --file="$query_file" \
    | sed '/^[[:space:]]*$/d' >> "$OUTPUT_FILE"; then
    collector_exit=1
    echo "Runtime pressure query failed after ${samples} successful samples." >&2
    exit "$collector_exit"
  fi
  samples=$((samples + 1))

  remaining=$((DURATION_SECONDS - (SECONDS - started_at)))
  if (( remaining <= 0 )); then
    break
  fi
  sleep_for="$INTERVAL_SECONDS"
  if (( sleep_for > remaining )); then
    sleep_for="$remaining"
  fi
  sleep "$sleep_for" &
  sleep_pid=$!
  wait "$sleep_pid" || true

done

printf 'LifeMate runtime pressure samples=%d output=%s status=%s target=%s\n' \
  "$samples" "$OUTPUT_FILE" "$STATUS_FILE" "$TARGET"
