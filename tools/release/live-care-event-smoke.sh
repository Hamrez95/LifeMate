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
  body="$(jq -cn --arg email "$email" --arg password "$password" \
    '{email:$email,password:$password}')"
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

uuid() {
  cat /proc/sys/kernel/random/uuid
}

bootstrap() {
  local token="$1"
  local display_name="$2"
  local body
  body="$(jq -cn --arg displayName "$display_name" \
    '{displayName:$displayName,locale:"fa",timeZone:"Asia/Tehran"}')"
  request POST "$token" '/api/v1/users/bootstrap' "$body" 200
  echo "$RESPONSE_BODY" | jq -er '.user.id'
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

request GET '' '/api/v1/me' '' 401

PATIENT_TOKEN="$(sign_in "$PATIENT_EMAIL" "$PATIENT_PASSWORD")"
CAREGIVER_TOKEN="$(sign_in "$CAREGIVER_EMAIL" "$CAREGIVER_PASSWORD")"
UNRELATED_TOKEN="$(sign_in "$UNRELATED_EMAIL" "$UNRELATED_PASSWORD")"

PATIENT_ID="$(bootstrap "$PATIENT_TOKEN" 'بیمار تست برنامه مراقبتی')"
CAREGIVER_ID="$(bootstrap "$CAREGIVER_TOKEN" 'مراقب تست برنامه مراقبتی')"
UNRELATED_ID="$(bootstrap "$UNRELATED_TOKEN" 'کاربر نامرتبط تست برنامه مراقبتی')"

# Resolve an active relationship left by an interrupted test run.
request GET "$PATIENT_TOKEN" '/api/v1/care/relationships' '' 200
while IFS= read -r relationship_id; do
  [[ -z "$relationship_id" ]] && continue
  request DELETE "$PATIENT_TOKEN" "/api/v1/care/relationships/$relationship_id" '' 204
done < <(echo "$RESPONSE_BODY" | jq -r \
  --arg caregiverId "$CAREGIVER_ID" \
  '.[] | select(.caregiverUserId == $caregiverId and .status == "active") | .id')

request GET "$PATIENT_TOKEN" '/api/v1/care/invitations' '' 200
pending_count="$(echo "$RESPONSE_BODY" \
  | jq '[.[] | select(.status == "pending")] | length')"
if [[ "$pending_count" != '0' ]]; then
  echo "Dedicated patient test account has a pending invitation." >&2
  exit 1
fi

LOCAL_DATE="$(TZ=Asia/Tehran date +%F)"
LOCAL_TIME="$(TZ=Asia/Tehran date -d '+2 hours' +%H:%M)"
RUN_SUFFIX="${EXPECTED_RELEASE_VERSION:0:8}-$(date +%s)"
CARE_EVENT_REQUEST_ID="$(uuid)"
CARE_EVENT_BODY="$(jq -cn \
  --arg requestId "$CARE_EVENT_REQUEST_ID" \
  --arg title "ویزیت کنترل‌شده $RUN_SUFFIX" \
  --arg date "$LOCAL_DATE" \
  --arg time "$LOCAL_TIME" \
  '{
    clientRequestId:$requestId,
    eventType:"appointment",
    title:$title,
    providerName:"پزشک تست انتشار",
    specialty:"قلب و عروق",
    medicationName:null,
    doseText:null,
    administrationRoute:null,
    reason:"تست کنترل‌شده قرارداد ویزیت",
    instructions:"این رکورد فقط متعلق به حساب تست داخلی است",
    centerName:"مرکز درمانی تست LifeMate",
    addressLine:"تهران، خیابان تست، پلاک ۱",
    phoneNumber:"02100000000",
    scheduledLocalDate:$date,
    scheduledLocalTime:$time,
    timeZone:"Asia/Tehran"
  }')"

request POST "$PATIENT_TOKEN" '/api/v1/care-events' "$CARE_EVENT_BODY" 201
CARE_EVENT_ID="$(echo "$RESPONSE_BODY" | jq -er '.id')"
[[ "$(echo "$RESPONSE_BODY" | jq -r '.eventType')" == 'appointment' ]]
[[ "$(echo "$RESPONSE_BODY" | jq -r '.addressLine')" == 'تهران، خیابان تست، پلاک ۱' ]]

# A transport retry with the same idempotency key must return the same resource.
request POST "$PATIENT_TOKEN" '/api/v1/care-events' "$CARE_EVENT_BODY" 201
[[ "$(echo "$RESPONSE_BODY" | jq -r '.id')" == "$CARE_EVENT_ID" ]]

request GET "$PATIENT_TOKEN" \
  "/api/v1/care-events?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" '' 200
echo "$RESPONSE_BODY" | jq -e \
  --arg eventId "$CARE_EVENT_ID" \
  '.[] | select(.id == $eventId and .eventType == "appointment")' >/dev/null

# No caregiver or unrelated user may read the event before consent.
request GET "$CAREGIVER_TOKEN" \
  "/api/v1/care/patients/$PATIENT_ID/care-events?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" \
  '' 403
request GET "$UNRELATED_TOKEN" \
  "/api/v1/care/patients/$PATIENT_ID/care-events?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" \
  '' 403

INVITATION_BODY="$(jq -cn --arg contact "$CAREGIVER_EMAIL" \
  '{contactType:"email",contact:$contact,consentVersion:"care-patient-consent-v1",confirmConsent:true}')"
request POST "$PATIENT_TOKEN" '/api/v1/care/invitations' "$INVITATION_BODY" 201
INVITATION_TOKEN="$(echo "$RESPONSE_BODY" | jq -er '.token')"
ACCEPT_BODY="$(jq -cn --arg token "$INVITATION_TOKEN" \
  '{token:$token,consentVersion:"care-caregiver-consent-v1",confirmConsent:true}')"

request POST "$UNRELATED_TOKEN" '/api/v1/care/invitations/accept' "$ACCEPT_BODY" 403
request POST "$CAREGIVER_TOKEN" '/api/v1/care/invitations/accept' "$ACCEPT_BODY" 200
RELATIONSHIP_ID="$(echo "$RESPONSE_BODY" | jq -er '.id')"

request GET "$CAREGIVER_TOKEN" \
  "/api/v1/care/patients/$PATIENT_ID/care-events?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" \
  '' 200
echo "$RESPONSE_BODY" | jq -e \
  --arg eventId "$CARE_EVENT_ID" \
  '.[] | select(.id == $eventId and .addressLine == "تهران، خیابان تست، پلاک ۱")' \
  >/dev/null

request GET "$UNRELATED_TOKEN" \
  "/api/v1/care/patients/$PATIENT_ID/care-events?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" \
  '' 403

request DELETE "$PATIENT_TOKEN" "/api/v1/care/relationships/$RELATIONSHIP_ID" '' 204
request DELETE "$PATIENT_TOKEN" "/api/v1/care/relationships/$RELATIONSHIP_ID" '' 204
request GET "$CAREGIVER_TOKEN" \
  "/api/v1/care/patients/$PATIENT_ID/care-events?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" \
  '' 403

jq -n \
  --arg release "$EXPECTED_RELEASE_VERSION" \
  --arg patientUserId "$PATIENT_ID" \
  --arg caregiverUserId "$CAREGIVER_ID" \
  --arg unrelatedUserId "$UNRELATED_ID" \
  --arg relationshipId "$RELATIONSHIP_ID" \
  --arg careEventId "$CARE_EVENT_ID" \
  '{
    status:"passed",
    release:$release,
    roles:{
      patient:$patientUserId,
      caregiver:$caregiverUserId,
      unrelated:$unrelatedUserId
    },
    relationshipId:$relationshipId,
    careEventId:$careEventId
  }'
