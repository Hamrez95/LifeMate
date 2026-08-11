#!/usr/bin/env bash
set -euo pipefail

umask 077

required_vars=(
  WELLMATE_KEYSTORE_BASE64
  WELLMATE_STORE_PASSWORD
  WELLMATE_KEY_PASSWORD
  WELLMATE_KEY_ALIAS
  CAREMATE_KEYSTORE_BASE64
  CAREMATE_STORE_PASSWORD
  CAREMATE_KEY_PASSWORD
  CAREMATE_KEY_ALIAS
)

for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Required Android signing secret is missing: $name"
    exit 1
  fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
signing_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lifemate-android-signing"
rm -rf "$signing_dir"
mkdir -p "$signing_dir"

wellmate_store="$signing_dir/wellmate-release.jks"
caremate_store="$signing_dir/caremate-release.jks"

printf '%s' "$WELLMATE_KEYSTORE_BASE64" | base64 --decode > "$wellmate_store"
printf '%s' "$CAREMATE_KEYSTORE_BASE64" | base64 --decode > "$caremate_store"
chmod 600 "$wellmate_store" "$caremate_store"

test -s "$wellmate_store"
test -s "$caremate_store"

keytool -list \
  -keystore "$wellmate_store" \
  -storepass "$WELLMATE_STORE_PASSWORD" \
  -alias "$WELLMATE_KEY_ALIAS" >/dev/null

keytool -list \
  -keystore "$caremate_store" \
  -storepass "$CAREMATE_STORE_PASSWORD" \
  -alias "$CAREMATE_KEY_ALIAS" >/dev/null

property_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  value="${value//=/\\=}"
  value="${value//:/\\:}"
  value="${value// /\\ }"
  printf '%s' "$value"
}

write_properties() {
  local output="$1"
  local store_file="$2"
  local store_password="$3"
  local key_password="$4"
  local alias="$5"

  mkdir -p "$(dirname "$output")"
  {
    printf 'storePassword=%s\n' "$(property_escape "$store_password")"
    printf 'keyPassword=%s\n' "$(property_escape "$key_password")"
    printf 'keyAlias=%s\n' "$(property_escape "$alias")"
    printf 'storeFile=%s\n' "$(property_escape "$store_file")"
  } > "$output"
  chmod 600 "$output"
}

write_properties \
  "$repo_root/wellmate/android/key.properties" \
  "$wellmate_store" \
  "$WELLMATE_STORE_PASSWORD" \
  "$WELLMATE_KEY_PASSWORD" \
  "$WELLMATE_KEY_ALIAS"

write_properties \
  "$repo_root/caremate/android/key.properties" \
  "$caremate_store" \
  "$CAREMATE_STORE_PASSWORD" \
  "$CAREMATE_KEY_PASSWORD" \
  "$CAREMATE_KEY_ALIAS"

wellmate_fingerprint="$(keytool -list -v -keystore "$wellmate_store" -storepass "$WELLMATE_STORE_PASSWORD" -alias "$WELLMATE_KEY_ALIAS" | awk '/SHA256:/{print $2; exit}')"
caremate_fingerprint="$(keytool -list -v -keystore "$caremate_store" -storepass "$CAREMATE_STORE_PASSWORD" -alias "$CAREMATE_KEY_ALIAS" | awk '/SHA256:/{print $2; exit}')"

test -n "$wellmate_fingerprint"
test -n "$caremate_fingerprint"
printf '%s\n' "$wellmate_fingerprint" > "$signing_dir/wellmate-cert-sha256.txt"
printf '%s\n' "$caremate_fingerprint" > "$signing_dir/caremate-cert-sha256.txt"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'LIFEMATE_ANDROID_SIGNING_DIR=%s\n' "$signing_dir" >> "$GITHUB_ENV"
fi

printf 'Stable Android signing material prepared for WellMate and CareMate.\n'
printf 'Certificate fingerprints are stored as non-secret CI evidence.\n'
