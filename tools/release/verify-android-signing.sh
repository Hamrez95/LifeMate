#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <wellmate-apk> <caremate-apk>" >&2
  exit 2
fi

wellmate_apk="$1"
caremate_apk="$2"
signing_dir="${LIFEMATE_ANDROID_SIGNING_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lifemate-android-signing}"

apksigner_bin="$(find "${ANDROID_HOME:?ANDROID_HOME is required}/build-tools" -type f -name apksigner | sort -V | tail -n 1)"
test -x "$apksigner_bin"

normalize_digest() {
  tr '[:upper:]' '[:lower:]' | tr -d ':[:space:]'
}

verify_one() {
  local app="$1"
  local apk="$2"
  local expected_file="$3"
  local report="${RUNNER_TEMP:-/tmp}/$app-apksigner.txt"

  test -s "$apk"
  test -s "$expected_file"

  "$apksigner_bin" verify --verbose --print-certs "$apk" >"$report"

  local expected actual
  expected="$(normalize_digest < "$expected_file")"
  actual="$(sed -n -E 's/^Signer #[0-9]+ certificate SHA-256 digest:[[:space:]]*//p' "$report" | head -n 1 | normalize_digest)"

  if [[ -z "$actual" ]]; then
    echo "::error::$app APK signer SHA-256 could not be parsed from apksigner output."
    grep -E '^Signer #[0-9]+ certificate (DN|SHA-256 digest):' "$report" || true
    exit 1
  fi

  # Certificate fingerprints are public identifiers, not secret key material.
  printf '%s expected-signing-cert-sha256=%s\n' "$app" "$expected"
  printf '%s actual-apk-signing-cert-sha256=%s\n' "$app" "$actual"

  if [[ "$actual" != "$expected" ]]; then
    echo "::error::$app APK signing certificate does not match the founder-owned keystore prepared for this build."
    exit 1
  fi

  printf '%s signature verified.\n' "$app"
}

verify_one wellmate "$wellmate_apk" "$signing_dir/wellmate-cert-sha256.txt"
verify_one caremate "$caremate_apk" "$signing_dir/caremate-cert-sha256.txt"
