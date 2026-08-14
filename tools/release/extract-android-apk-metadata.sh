#!/usr/bin/env bash
set -euo pipefail

if (( $# != 3 )); then
  echo 'Usage: extract-android-apk-metadata.sh <apk> <aapt-bin> <expected-package-id>' >&2
  exit 2
fi

apk="$1"
aapt_bin="$2"
expected_package="$3"

if [[ ! -f "$apk" ]]; then
  echo "APK not found: $apk" >&2
  exit 2
fi
if [[ ! -x "$aapt_bin" ]]; then
  echo "aapt is not executable: $aapt_bin" >&2
  exit 2
fi
if [[ -z "$expected_package" ]]; then
  echo 'Expected package id is required.' >&2
  exit 2
fi

badging="$($aapt_bin dump badging "$apk")"
package_id="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$badging" | head -n 1)"
min_sdk="$(sed -n "s/^sdkVersion:'\([^']*\)'.*/\1/p" <<<"$badging" | head -n 1)"
target_sdk="$(sed -n "s/^targetSdkVersion:'\([^']*\)'.*/\1/p" <<<"$badging" | head -n 1)"
max_sdk="$(sed -n "s/^maxSdkVersion:'\([^']*\)'.*/\1/p" <<<"$badging" | head -n 1)"
version_code="$(sed -n "s/^package: .*versionCode='\([^']*\)'.*/\1/p" <<<"$badging" | head -n 1)"
version_name="$(sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p" <<<"$badging" | head -n 1)"

if [[ "$package_id" != "$expected_package" ]]; then
  echo "Unexpected Android package id: expected '$expected_package', got '$package_id'." >&2
  exit 1
fi
for value_name in min_sdk target_sdk version_code version_name; do
  value="${!value_name}"
  if [[ -z "$value" ]]; then
    echo "APK metadata is missing required field: $value_name" >&2
    exit 1
  fi
done
if ! [[ "$min_sdk" =~ ^[0-9]+$ && "$target_sdk" =~ ^[0-9]+$ && "$version_code" =~ ^[0-9]+$ ]]; then
  echo 'APK SDK/version metadata must be numeric.' >&2
  exit 1
fi
if (( min_sdk > target_sdk )); then
  echo "Invalid APK SDK range: minSdk $min_sdk exceeds targetSdk $target_sdk." >&2
  exit 1
fi
if [[ -n "$max_sdk" ]] && ! [[ "$max_sdk" =~ ^[0-9]+$ ]]; then
  echo 'APK maxSdkVersion must be numeric when present.' >&2
  exit 1
fi

jq -n \
  --arg packageId "$package_id" \
  --argjson minSdk "$min_sdk" \
  --argjson targetSdk "$target_sdk" \
  --arg maxSdk "$max_sdk" \
  --argjson versionCode "$version_code" \
  --arg versionName "$version_name" \
  '{
    packageId: $packageId,
    minSdk: $minSdk,
    targetSdk: $targetSdk,
    maxSdk: (if $maxSdk == "" then null else ($maxSdk | tonumber) end),
    versionCode: $versionCode,
    versionName: $versionName
  }'
