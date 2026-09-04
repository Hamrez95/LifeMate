#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_dir="$repo_root/cocoonmate"
production_project_ref="bwdvmniywyyijjauipnh"

fail() {
  echo "::error::$*" >&2
  exit 1
}

verify_environment() {
  local release_environment="${LIFEMATE_RELEASE_ENVIRONMENT:-}"
  local supabase_url="${SUPABASE_URL:-}"
  local api_base_url="${LIFEMATE_API_BASE_URL:-}"

  [[ "$release_environment" =~ ^(ci|production|nonproduction)$ ]] || \
    fail "LIFEMATE_RELEASE_ENVIRONMENT must be ci, production, or nonproduction."
  [[ "$supabase_url" =~ ^https://[^/]+$ ]] || \
    fail "SUPABASE_URL must be an HTTPS origin without a path."
  [[ "$api_base_url" =~ ^https://[^/]+/functions/v1/lifemate-api$ ]] || \
    fail "LIFEMATE_API_BASE_URL must target the canonical lifemate-api function path."

  local supabase_host api_host
  supabase_host="${supabase_url#https://}"
  api_host="${api_base_url#https://}"
  api_host="${api_host%%/*}"
  [[ "$supabase_host" = "$api_host" ]] || \
    fail "Supabase and LifeMate API origins must belong to the same environment."

  local production_host="${production_project_ref}.supabase.co"
  if [[ "$release_environment" = "production" ]]; then
    [[ "$supabase_host" = "$production_host" ]] || \
      fail "Production candidate is not bound to the canonical production project."
  elif [[ "$release_environment" = "nonproduction" ]]; then
    [[ "$supabase_host" != "$production_host" ]] || \
      fail "Non-production candidate must not use the production project."
  fi
}

prepare_android() {
  command -v flutter >/dev/null 2>&1 || fail "flutter is required"
  [[ -f "$app_dir/pubspec.yaml" ]] || fail "cocoonmate/pubspec.yaml is missing"

  (
    cd "$app_dir"
    flutter create \
      --platforms=android \
      --org com.mylifemate \
      --project-name cocoonmate \
      .
  )

  local manifest="$app_dir/android/app/src/main/AndroidManifest.xml"
  local gradle="$app_dir/android/app/build.gradle.kts"
  [[ -f "$manifest" ]] || fail "generated AndroidManifest.xml is missing"
  [[ -f "$gradle" ]] || fail "generated Android build.gradle.kts is missing"

  python3 - "$manifest" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
if 'android:label="cocoonmate"' not in text:
    raise SystemExit('generated Cocoon label contract changed')
text = text.replace('android:label="cocoonmate"', 'android:label="CocoonMate"', 1)
if 'android:icon="@mipmap/ic_launcher"' not in text:
    raise SystemExit('generated launcher icon contract changed')
text = text.replace(
    'android:icon="@mipmap/ic_launcher"',
    'android:icon="@drawable/cocoon_launcher" android:roundIcon="@drawable/cocoon_launcher"',
    1,
)
path.write_text(text)
PY

  mkdir -p "$app_dir/android/app/src/main/res/drawable"
  cat > "$app_dir/android/app/src/main/res/drawable/cocoon_launcher.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#B75D88"
        android:pathData="M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5C2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3C19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z" />
</vector>
XML

  grep -Fq 'applicationId = "com.mylifemate.cocoonmate"' "$gradle" || \
    fail "Cocoon Android applicationId is not isolated."
  grep -Fq 'android:label="CocoonMate"' "$manifest" || \
    fail "Cocoon Android display name is missing."
  grep -Fq '@drawable/cocoon_launcher' "$manifest" || \
    fail "Cocoon Android launcher identity is missing."
}

case "${1:-prepare}" in
  verify-environment)
    verify_environment
    ;;
  prepare)
    verify_environment
    prepare_android
    ;;
  *)
    fail "Usage: $0 [prepare|verify-environment]"
    ;;
esac
