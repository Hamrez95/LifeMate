#!/usr/bin/env bash
set -euo pipefail

# Android requires every update to use a versionCode greater than the installed
# APK. GitHub GITHUB_RUN_NUMBER is scoped per workflow, so using it directly can
# make an internal build newer than a later main build. Use one repository-wide
# time scale instead: UTC seconds since 2025-01-01.
#
# This remains well below Android's 2,100,000,000 versionCode ceiling for many
# decades and is monotonic across all LifeMate Android workflows.
base_epoch=1735689600 # 2025-01-01T00:00:00Z
now_epoch="$(date -u +%s)"
version_code=$((now_epoch - base_epoch))

if (( version_code <= 0 || version_code > 2100000000 )); then
  echo "Android versionCode is outside the supported range: $version_code" >&2
  exit 1
fi

printf '%s\n' "$version_code"
