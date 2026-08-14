#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"

INTERVAL_SECONDS="${INTERVAL_SECONDS:-5}"
DURATION_SECONDS="${DURATION_SECONDS:-120}"
OUTPUT_FILE="${OUTPUT_FILE:-runtime-pressure.ndjson}"
TARGET="${LIFEMATE_OBSERVABILITY_TARGET:-local}"

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

started_at=$SECONDS
samples=0
while (( SECONDS - started_at < DURATION_SECONDS )); do
  psql "$DATABASE_URL" \
    --no-psqlrc \
    --tuples-only \
    --no-align \
    --set=ON_ERROR_STOP=1 \
    --file="$query_file" \
    | sed '/^[[:space:]]*$/d' >> "$OUTPUT_FILE"
  samples=$((samples + 1))
  sleep "$INTERVAL_SECONDS"
done

printf 'LifeMate runtime pressure samples=%d output=%s target=%s\n' \
  "$samples" "$OUTPUT_FILE" "$TARGET"
