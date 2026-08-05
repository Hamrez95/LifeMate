#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  SUPABASE_URL
  SUPABASE_PUBLISHABLE_KEY
  LIFEMATE_API_BASE_URL
  EXPECTED_RELEASE_VERSION
  PATIENT_EMAIL
  PATIENT_PASSWORD
  CAREGIVER_EMAIL
  CAREGIVER_PASSWORD
  UNRELATED_EMAIL
  UNRELATED_PASSWORD
)
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required environment variable: $name" >&2
    exit 2
  fi
done

for command in curl jq date; do
  command -v "$command" >/dev/null || {
    echo "Required command is unavailable: $command" >&2
    exit 2
  }
done

API_BASE="${LIFEMATE_API_BASE_URL%/}"
SUPABASE_BASE="${SUPABASE_URL%/}"
RESPONSE_BODY=''

cleanup() {
  unset PATIENT_TOKEN CAREGIVER_TOKEN UNRELATED_TOKEN
}
trap cleanup EXIT

sign_in() {
  local email="$1"
  local password="$2"
  local body
  body="$(jq -cn --arg email "$email" --arg password "$password" '{email:$email,password:$password}')"
  curl --fail --silent --show-error \
    --request POST \
    --header "apikey: $SUPABASE_PUBLISHABLE_KEY" \
    --header 'Content-Type: application/json' \
    --data "$body" \
    "$SUPABASE_BASE/auth/v1/token?grant_type=password" \
    | jq -er '.access_token'
}

request() {
  local method="$1"
  local token="$2"
  local path="$3"
  local body="${4:-}"
  local expected_status="$5"
  local response_file
  local status
  response_file="$(mktemp)"

  local -a args=(
    --silent --show-error
    --request "$method"
    --output "$response_file"
    --write-out '%{http_code}'
    --header 'Accept: application/json'
  )
  if [[ -n "$token" ]]; then
    args+=(--header "Authorization: Bearer $token")
  fi
  if [[ -n "$body" ]]; then
    args+=(--header 'Content-Type: application/json' --data "$body")
  fi

  status="$(curl "${args[@]}" "$API_BASE$path")"
  RESPONSE_BODY="$(cat "$response_file")"
  rm -f "$response_file"

  if [[ "$status" != "$expected_status" ]]; then
    echo "Unexpected HTTP status for $method $path: expected $expected_status, got $status" >&2
    if [[ -n "$RESPONSE_BODY" ]]; then
      echo "$RESPONSE_BODY" \
        | jq -c '{status,code,title,detail,correlationId}' 2>/dev/null >&2 \
        || true
    fi
    exit 1
  fi
}

health_file="$(mktemp)"
health_status="$(curl --silent --show-error --retry 3 --retry-all-errors \
  --output "$health_file" --write-out '%{http_code}' "$API_BASE/health")"
health_body="$(cat "$health_file")"
rm -f "$health_file"
[[ "$health_status" == '200' ]] || {
  echo "Health endpoint returned $health_status" >&2
  exit 1
}
echo "$health_body" | jq -e \
  --arg version "$EXPECTED_RELEASE_VERSION" \
  '.status == "ok" and .database == "ready" and .version == $version' \
  >/dev/null

PATIENT_TOKEN="$(sign_in "$PATIENT_EMAIL" "$PATIENT_PASSWORD")"
CAREGIVER_TOKEN="$(sign_in "$CAREGIVER_EMAIL" "$CAREGIVER_PASSWORD")"
UNRELATED_TOKEN="$(sign_in "$UNRELATED_EMAIL" "$UNRELATED_PASSWORD")"

request GET "$PATIENT_TOKEN" '/api/v1/me' '' 200
PATIENT_ID="$(echo "$RESPONSE_BODY" | jq -er '.user.id')"
request GET "$CAREGIVER_TOKEN" '/api/v1/me' '' 200
CAREGIVER_ID="$(echo "$RESPONSE_BODY" | jq -er '.user.id')"
request GET "$UNRELATED_TOKEN" '/api/v1/me' '' 200
UNRELATED_ID="$(echo "$RESPONSE_BODY" | jq -er '.user.id')"

# Exercise the stable database profile contract on the candidate. The API must
# work both before and after the additive integer-version migration is promoted.
request GET "$PATIENT_TOKEN" '/api/v1/me/profile' '' 200
PROFILE_VERSION="$(echo "$RESPONSE_BODY" | jq -er '.version | numbers')"
PROFILE_NAME="$(echo "$RESPONSE_BODY" | jq -er '.displayName')"
PROFILE_PHONE="$(echo "$RESPONSE_BODY" | jq -r '.phoneNumber // ""')"
PROFILE_LOCALE="$(echo "$RESPONSE_BODY" | jq -er '.locale')"
PROFILE_TIME_ZONE="$(echo "$RESPONSE_BODY" | jq -er '.timeZone')"
PROFILE_BODY="$(jq -cn \
  --argjson version "$PROFILE_VERSION" \
  --arg displayName "$PROFILE_NAME" \
  --arg phoneNumber "$PROFILE_PHONE" \
  --arg locale "$PROFILE_LOCALE" \
  --arg timeZone "$PROFILE_TIME_ZONE" \
  '{version:$version,displayName:$displayName,phoneNumber:(if $phoneNumber == "" then null else $phoneNumber end),locale:$locale,timeZone:$timeZone}')"
request PATCH "$PATIENT_TOKEN" '/api/v1/me/profile' "$PROFILE_BODY" 200
UPDATED_PROFILE_VERSION="$(echo "$RESPONSE_BODY" | jq -er '.version | numbers')"
[[ "$UPDATED_PROFILE_VERSION" -gt "$PROFILE_VERSION" ]]
request PATCH "$PATIENT_TOKEN" '/api/v1/me/profile' "$PROFILE_BODY" 409
[[ "$(echo "$RESPONSE_BODY" | jq -r '.code')" == 'stale_profile' ]]

# QR invitations are ten-minute, one-use capabilities. A newer QR invalidates
# the previous pending QR, self-pairing is rejected and replay by another user
# is denied after the intended caregiver accepts it.
QR_BODY='{"consentVersion":"care-patient-consent-v1","confirmConsent":true}'
request POST "$PATIENT_TOKEN" '/api/v1/care/invitations/qr' "$QR_BODY" 201
FIRST_QR_TOKEN="$(echo "$RESPONSE_BODY" | jq -er '.token')"
request POST "$PATIENT_TOKEN" '/api/v1/care/invitations/qr' "$QR_BODY" 201
SECOND_QR_TOKEN="$(echo "$RESPONSE_BODY" | jq -er '.token')"
QR_EXPIRES_AT="$(echo "$RESPONSE_BODY" | jq -er '.expiresAtUtc')"

now_epoch="$(date -u +%s)"
expires_epoch="$(date -u -d "$QR_EXPIRES_AT" +%s)"
remaining_seconds="$((expires_epoch - now_epoch))"
[[ "$remaining_seconds" -gt 0 && "$remaining_seconds" -le 600 ]]

first_accept_body="$(jq -cn --arg token "$FIRST_QR_TOKEN" '{token:$token,consentVersion:"care-caregiver-consent-v1",confirmConsent:true}')"
second_accept_body="$(jq -cn --arg token "$SECOND_QR_TOKEN" '{token:$token,consentVersion:"care-caregiver-consent-v1",confirmConsent:true}')"
request POST "$CAREGIVER_TOKEN" '/api/v1/care/invitations/accept' "$first_accept_body" 409
request POST "$PATIENT_TOKEN" '/api/v1/care/invitations/accept' "$second_accept_body" 400
[[ "$(echo "$RESPONSE_BODY" | jq -r '.code')" == 'self_invitation_not_allowed' ]]
request POST "$CAREGIVER_TOKEN" '/api/v1/care/invitations/accept' "$second_accept_body" 200
RELATIONSHIP_ID="$(echo "$RESPONSE_BODY" | jq -er '.id')"
request POST "$CAREGIVER_TOKEN" '/api/v1/care/invitations/accept' "$second_accept_body" 200
[[ "$(echo "$RESPONSE_BODY" | jq -r '.id')" == "$RELATIONSHIP_ID" ]]
request POST "$UNRELATED_TOKEN" '/api/v1/care/invitations/accept' "$second_accept_body" 409

LOCAL_DATE="$(TZ=Asia/Tehran date +%F)"
request GET "$CAREGIVER_TOKEN" "/api/v1/care/patients/$PATIENT_ID/dose-occurrences?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" '' 200
request GET "$UNRELATED_TOKEN" "/api/v1/care/patients/$PATIENT_ID/dose-occurrences?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" '' 403

request DELETE "$CAREGIVER_TOKEN" "/api/v1/care/relationships/$RELATIONSHIP_ID" '' 204
request GET "$CAREGIVER_TOKEN" "/api/v1/care/patients/$PATIENT_ID/dose-occurrences?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" '' 403

jq -n \
  --arg release "$EXPECTED_RELEASE_VERSION" \
  --arg patientUserId "$PATIENT_ID" \
  --arg caregiverUserId "$CAREGIVER_ID" \
  --arg unrelatedUserId "$UNRELATED_ID" \
  --arg relationshipId "$RELATIONSHIP_ID" \
  --argjson profileVersion "$UPDATED_PROFILE_VERSION" \
  '{status:"passed",release:$release,profileVersion:$profileVersion,roles:{patient:$patientUserId,caregiver:$caregiverUserId,unrelated:$unrelatedUserId},qrRelationshipId:$relationshipId}'
