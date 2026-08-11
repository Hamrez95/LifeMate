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

  test -s "$apk"
  test -s "$expected_file"

  "$apksigner_bin" verify --verbose --print-certs "$apk" >/tmp/"$app"-apksigner.txt

  local expected actual
  expected="$(normalize_digest < "$expected_file")"
  actual="$(awk -F': ' '/certificate SHA-256 digest:/{print $2; exit}' /tmp/"$app"-apksigner.txt | normalize_digest)"

  if [[ -z "$actual" || "$actual" != "$expected" ]]; then
    echo "::error::$app APK signing certificate does not match the founder-owned keystore prepared for this build."
    exit 1
  fi

  printf '%s=%s\n' "$app" "$expected"
}

verify_one wellmate "$wellmate_apk" "$signing_dir/wellmate-cert-sha256.txt"
verify_one caremate "$caremate_apk" "$signing_dir/caremate-cert-sha256.txt"
