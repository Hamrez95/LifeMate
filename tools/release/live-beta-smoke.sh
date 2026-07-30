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
      echo "$RESPONSE_BODY" | jq -c '{status,code,title,detail,correlationId}' 2>/dev/null >&2 || true
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
  body="$(jq -cn --arg displayName "$display_name" '{displayName:$displayName,locale:"fa",timeZone:"Asia/Tehran"}')"
  request POST "$token" '/api/v1/users/bootstrap' "$body" 200
  echo "$RESPONSE_BODY" | jq -er '.user.id'
}

create_occurrence() {
  local token="$1"
  local medication_name="$2"
  local local_date="$3"
  local weekday="$4"
  local local_time="$5"
  local medication_body medication_id plan_body plan_id

  medication_body="$(jq -cn --arg name "$medication_name" '{name:$name,strengthText:"10 mg",form:"tablet",notes:null}')"
  request POST "$token" '/api/v1/medications' "$medication_body" 201
  medication_id="$(echo "$RESPONSE_BODY" | jq -er '.id')"

  plan_body="$(jq -cn \
    --arg medicationId "$medication_id" \
    --arg date "$local_date" \
    --arg dayOfWeek "$weekday" \
    --arg localTime "$local_time" \
    '{medicationId:$medicationId,doseText:"یک عدد",instructions:"تست کنترل‌شده انتشار",startDate:$date,endDate:$date,timeZone:"Asia/Tehran",schedules:[{dayOfWeek:$dayOfWeek,localTime:$localTime}]}')"
  request POST "$token" '/api/v1/treatment-plans' "$plan_body" 201
  plan_id="$(echo "$RESPONSE_BODY" | jq -er '.id')"

  request GET "$token" "/api/v1/dose-occurrences?fromDate=$local_date&toDate=$local_date" '' 200
  echo "$RESPONSE_BODY" | jq -ec --arg planId "$plan_id" '.[] | select(.treatmentPlanId == $planId)' | head -n 1
}

health_file="$(mktemp)"
health_status="$(curl --silent --show-error --retry 3 --retry-all-errors \
  --output "$health_file" --write-out '%{http_code}' "$API_BASE/health")"
health_body="$(cat "$health_file")"
rm -f "$health_file"
[[ "$health_status" == '200' ]] || { echo "Health endpoint returned $health_status" >&2; exit 1; }
echo "$health_body" | jq -e \
  --arg version "$EXPECTED_RELEASE_VERSION" \
  '.status == "ok" and .database == "ready" and .version == $version' >/dev/null

request GET '' '/api/v1/me' '' 401

PATIENT_TOKEN="$(sign_in "$PATIENT_EMAIL" "$PATIENT_PASSWORD")"
CAREGIVER_TOKEN="$(sign_in "$CAREGIVER_EMAIL" "$CAREGIVER_PASSWORD")"
UNRELATED_TOKEN="$(sign_in "$UNRELATED_EMAIL" "$UNRELATED_PASSWORD")"

PATIENT_ID="$(bootstrap "$PATIENT_TOKEN" 'بیمار حرفه‌ای تست')"
CAREGIVER_ID="$(bootstrap "$CAREGIVER_TOKEN" 'مراقب حرفه‌ای تست')"
UNRELATED_ID="$(bootstrap "$UNRELATED_TOKEN" 'کاربر نامرتبط تست')"

# Clean only an already-active relationship between the two dedicated test accounts.
request GET "$PATIENT_TOKEN" '/api/v1/care/relationships' '' 200
while IFS= read -r relationship_id; do
  [[ -z "$relationship_id" ]] && continue
  request DELETE "$PATIENT_TOKEN" "/api/v1/care/relationships/$relationship_id" '' 204
done < <(echo "$RESPONSE_BODY" | jq -r \
  --arg caregiverId "$CAREGIVER_ID" \
  '.[] | select(.caregiverUserId == $caregiverId and .status == "active") | .id')

# A prior interrupted release must be resolved rather than silently bypassed.
request GET "$PATIENT_TOKEN" '/api/v1/care/invitations' '' 200
pending_count="$(echo "$RESPONSE_BODY" | jq '[.[] | select(.status == "pending")] | length')"
if [[ "$pending_count" != '0' ]]; then
  echo "Dedicated patient test account has a pending invitation. Revoke/expire it before rerunning live release smoke." >&2
  exit 1
fi

LOCAL_DATE="$(TZ=Asia/Tehran date +%F)"
WEEKDAY="$(TZ=Asia/Tehran date +%A)"
LOCAL_TIME="$(TZ=Asia/Tehran date +%H:%M)"
RUN_SUFFIX="${EXPECTED_RELEASE_VERSION:0:8}-$(date +%s)"

PATIENT_OCCURRENCE="$(create_occurrence "$PATIENT_TOKEN" "داروی تست بیمار $RUN_SUFFIX" "$LOCAL_DATE" "$WEEKDAY" "$LOCAL_TIME")"
PATIENT_OCCURRENCE_ID="$(echo "$PATIENT_OCCURRENCE" | jq -er '.id')"
PATIENT_VERSION="$(echo "$PATIENT_OCCURRENCE" | jq -er '.version')"
SHARED_REQUEST_ID="$(uuid)"
REPORTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REPORT_BODY="$(jq -cn \
  --arg requestId "$SHARED_REQUEST_ID" \
  --arg occurredAt "$REPORTED_AT" \
  --argjson version "$PATIENT_VERSION" \
  '{clientRequestId:$requestId,version:$version,status:"taken",occurredAtUtc:$occurredAt}')"

request POST "$PATIENT_TOKEN" "/api/v1/dose-occurrences/$PATIENT_OCCURRENCE_ID/report" "$REPORT_BODY" 200
[[ "$(echo "$RESPONSE_BODY" | jq -r '.status')" == 'taken' ]]
request POST "$PATIENT_TOKEN" "/api/v1/dose-occurrences/$PATIENT_OCCURRENCE_ID/report" "$REPORT_BODY" 200
[[ "$(echo "$RESPONSE_BODY" | jq -r '.id')" == "$PATIENT_OCCURRENCE_ID" ]]

request POST "$UNRELATED_TOKEN" "/api/v1/dose-occurrences/$PATIENT_OCCURRENCE_ID/report" "$REPORT_BODY" 404

UNRELATED_OCCURRENCE="$(create_occurrence "$UNRELATED_TOKEN" "داروی تست نامرتبط $RUN_SUFFIX" "$LOCAL_DATE" "$WEEKDAY" "$LOCAL_TIME")"
UNRELATED_OCCURRENCE_ID="$(echo "$UNRELATED_OCCURRENCE" | jq -er '.id')"
UNRELATED_VERSION="$(echo "$UNRELATED_OCCURRENCE" | jq -er '.version')"
UNRELATED_REPORT_BODY="$(echo "$REPORT_BODY" | jq --argjson version "$UNRELATED_VERSION" '.version=$version')"
request POST "$UNRELATED_TOKEN" "/api/v1/dose-occurrences/$UNRELATED_OCCURRENCE_ID/report" "$UNRELATED_REPORT_BODY" 200

INVITATION_BODY="$(jq -cn --arg contact "$CAREGIVER_EMAIL" '{contactType:"email",contact:$contact,consentVersion:"care-patient-consent-v1",confirmConsent:true}')"
request POST "$PATIENT_TOKEN" '/api/v1/care/invitations' "$INVITATION_BODY" 201
INVITATION_TOKEN="$(echo "$RESPONSE_BODY" | jq -er '.token')"
ACCEPT_BODY="$(jq -cn --arg token "$INVITATION_TOKEN" '{token:$token,consentVersion:"care-caregiver-consent-v1",confirmConsent:true}')"

request POST "$UNRELATED_TOKEN" '/api/v1/care/invitations/accept' "$ACCEPT_BODY" 403
request POST "$CAREGIVER_TOKEN" '/api/v1/care/invitations/accept' "$ACCEPT_BODY" 200
RELATIONSHIP_ID="$(echo "$RESPONSE_BODY" | jq -er '.id')"
request POST "$CAREGIVER_TOKEN" '/api/v1/care/invitations/accept' "$ACCEPT_BODY" 200
[[ "$(echo "$RESPONSE_BODY" | jq -r '.id')" == "$RELATIONSHIP_ID" ]]

request GET "$CAREGIVER_TOKEN" "/api/v1/care/patients/$PATIENT_ID/dose-occurrences?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" '' 200
echo "$RESPONSE_BODY" | jq -e --arg occurrenceId "$PATIENT_OCCURRENCE_ID" '.[] | select(.id == $occurrenceId and .status == "taken")' >/dev/null
request GET "$UNRELATED_TOKEN" "/api/v1/care/patients/$PATIENT_ID/dose-occurrences?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" '' 403

request DELETE "$PATIENT_TOKEN" "/api/v1/care/relationships/$RELATIONSHIP_ID" '' 204
request DELETE "$PATIENT_TOKEN" "/api/v1/care/relationships/$RELATIONSHIP_ID" '' 204
request GET "$CAREGIVER_TOKEN" "/api/v1/care/patients/$PATIENT_ID/dose-occurrences?fromDate=$LOCAL_DATE&toDate=$LOCAL_DATE" '' 403

request GET "$PATIENT_TOKEN" '/api/v1/medications' '' 200
echo "$RESPONSE_BODY" | jq -e --arg name "داروی تست بیمار $RUN_SUFFIX" '.[] | select(.name == $name)' >/dev/null

jq -n \
  --arg release "$EXPECTED_RELEASE_VERSION" \
  --arg patientUserId "$PATIENT_ID" \
  --arg caregiverUserId "$CAREGIVER_ID" \
  --arg unrelatedUserId "$UNRELATED_ID" \
  --arg relationshipId "$RELATIONSHIP_ID" \
  --arg occurrenceId "$PATIENT_OCCURRENCE_ID" \
  '{status:"passed",release:$release,roles:{patient:$patientUserId,caregiver:$caregiverUserId,unrelated:$unrelatedUserId},relationshipId:$relationshipId,occurrenceId:$occurrenceId}'
