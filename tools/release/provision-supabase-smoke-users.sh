#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
if [[ "$mode" != 'create' && "$mode" != 'delete' ]]; then
  echo 'Usage: provision-supabase-smoke-users.sh create|delete' >&2
  exit 2
fi

for name in SUPABASE_URL SUPABASE_PROJECT_REF; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 2
  fi
done

commands=(curl jq)
if [[ "$mode" == 'create' ]]; then
  commands+=(openssl)
fi
for command in "${commands[@]}"; do
  command -v "$command" >/dev/null || {
    echo "Required command is unavailable: $command" >&2
    exit 2
  }
done

SUPABASE_BASE="${SUPABASE_URL%/}"

admin_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local -a args=(
    --fail --silent --show-error
    --request "$method"
    --header "apikey: $SMOKE_SERVICE_ROLE_KEY"
    --header "Authorization: Bearer $SMOKE_SERVICE_ROLE_KEY"
    --header 'Content-Type: application/json'
  )
  if [[ -n "$body" ]]; then
    args+=(--data "$body")
  fi
  curl "${args[@]}" "$SUPABASE_BASE$path"
}

append_env() {
  local name="$1"
  local value="$2"
  printf '%s=%s\n' "$name" "$value" >> "$GITHUB_ENV"
}

if [[ "$mode" == 'create' ]]; then
  for name in SUPABASE_ACCESS_TOKEN GITHUB_RUN_ID GITHUB_ENV; do
    if [[ -z "${!name:-}" ]]; then
      echo "Missing required environment variable: $name" >&2
      exit 2
    fi
  done

  keys_response="$(curl --fail --silent --show-error \
    --header "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
    "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/api-keys?reveal=true")"
  SMOKE_SERVICE_ROLE_KEY="$(echo "$keys_response" | jq -er '
    map(select(.name == "service_role" or .name == "secret"))
    | sort_by(if .name == "service_role" then 0 else 1 end)
    | .[0].api_key
  ')"
  [[ -n "$SMOKE_SERVICE_ROLE_KEY" ]]
  echo "::add-mask::$SMOKE_SERVICE_ROLE_KEY"
  append_env SMOKE_SERVICE_ROLE_KEY "$SMOKE_SERVICE_ROLE_KEY"

  suffix="${GITHUB_RUN_ID}-$(openssl rand -hex 5)"
  PATIENT_EMAIL="lifemate-smoke-patient-$suffix@example.com"
  CAREGIVER_EMAIL="lifemate-smoke-caregiver-$suffix@example.com"
  UNRELATED_EMAIL="lifemate-smoke-unrelated-$suffix@example.com"
  PATIENT_PASSWORD="Lm!$(openssl rand -base64 30 | tr -d '\n')"
  CAREGIVER_PASSWORD="Lm!$(openssl rand -base64 30 | tr -d '\n')"
  UNRELATED_PASSWORD="Lm!$(openssl rand -base64 30 | tr -d '\n')"

  for secret in \
    "$PATIENT_EMAIL" "$PATIENT_PASSWORD" \
    "$CAREGIVER_EMAIL" "$CAREGIVER_PASSWORD" \
    "$UNRELATED_EMAIL" "$UNRELATED_PASSWORD"
  do
    echo "::add-mask::$secret"
  done

  create_user() {
    local email="$1"
    local password="$2"
    local role="$3"
    local body
    body="$(jq -cn \
      --arg email "$email" \
      --arg password "$password" \
      --arg role "$role" \
      --arg runId "$GITHUB_RUN_ID" \
      '{email:$email,password:$password,email_confirm:true,user_metadata:{lifemateSmoke:true,smokeRole:$role,githubRunId:$runId}}')"
    admin_request POST '/auth/v1/admin/users' "$body" | jq -er '.id'
  }

  SMOKE_PATIENT_ID="$(create_user "$PATIENT_EMAIL" "$PATIENT_PASSWORD" patient)"
  append_env SMOKE_PATIENT_ID "$SMOKE_PATIENT_ID"
  SMOKE_CAREGIVER_ID="$(create_user "$CAREGIVER_EMAIL" "$CAREGIVER_PASSWORD" caregiver)"
  append_env SMOKE_CAREGIVER_ID "$SMOKE_CAREGIVER_ID"
  SMOKE_UNRELATED_ID="$(create_user "$UNRELATED_EMAIL" "$UNRELATED_PASSWORD" unrelated)"
  append_env SMOKE_UNRELATED_ID "$SMOKE_UNRELATED_ID"

  append_env PATIENT_EMAIL "$PATIENT_EMAIL"
  append_env PATIENT_PASSWORD "$PATIENT_PASSWORD"
  append_env CAREGIVER_EMAIL "$CAREGIVER_EMAIL"
  append_env CAREGIVER_PASSWORD "$CAREGIVER_PASSWORD"
  append_env UNRELATED_EMAIL "$UNRELATED_EMAIL"
  append_env UNRELATED_PASSWORD "$UNRELATED_PASSWORD"

  jq -n '{status:"created",count:3}'
  exit 0
fi

ids=(
  "${SMOKE_PATIENT_ID:-}"
  "${SMOKE_CAREGIVER_ID:-}"
  "${SMOKE_UNRELATED_ID:-}"
)
present_count=0
for user_id in "${ids[@]}"; do
  if [[ -n "$user_id" ]]; then
    present_count=$((present_count + 1))
  fi
done

if [[ "$present_count" -eq 0 && -z "${SMOKE_SERVICE_ROLE_KEY:-}" ]]; then
  jq -n '{status:"skipped",reason:"not-provisioned"}'
  exit 0
fi
if [[ -z "${SMOKE_SERVICE_ROLE_KEY:-}" ]]; then
  echo 'Ephemeral users exist but the cleanup credential is unavailable.' >&2
  exit 2
fi

failures=0
deleted_count=0
for user_id in "${ids[@]}"; do
  [[ -z "$user_id" ]] && continue
  if admin_request DELETE "/auth/v1/admin/users/$user_id" >/dev/null; then
    deleted_count=$((deleted_count + 1))
  else
    echo "Failed to remove an ephemeral smoke user." >&2
    failures=$((failures + 1))
  fi
done

unset SMOKE_SERVICE_ROLE_KEY PATIENT_PASSWORD CAREGIVER_PASSWORD UNRELATED_PASSWORD
[[ "$failures" -eq 0 ]]
jq -n --argjson count "$deleted_count" '{status:"deleted",count:$count}'
