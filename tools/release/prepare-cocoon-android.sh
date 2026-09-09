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
  local python_bin="${PYTHON:-python3}"
  command -v "$python_bin" >/dev/null 2>&1 || fail "python3 is required"
  [[ -f "$app_dir/pubspec.yaml" ]] || fail "cocoonmate/pubspec.yaml is missing"

  (
    cd "$app_dir"
    flutter create \
      --platforms=android \
      --org com.mylifemate \
      --project-name cocoonmate \
      .
  )

  # flutter create adds template analysis/test files that do not belong to the
  # thin standalone host and can mask the real Cocoon test surface.
  rm -f "$app_dir/test/widget_test.dart" "$app_dir/analysis_options.yaml"

  local manifest="$app_dir/android/app/src/main/AndroidManifest.xml"
  local gradle="$app_dir/android/app/build.gradle.kts"
  [[ -f "$manifest" ]] || fail "generated AndroidManifest.xml is missing"
  [[ -f "$gradle" ]] || fail "generated Android build.gradle.kts is missing"

  "$python_bin" - "$manifest" "$gradle" <<'PY'
from pathlib import Path
import sys

manifest_path = Path(sys.argv[1])
gradle_path = Path(sys.argv[2])
text = manifest_path.read_text()
manifest_open = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
if manifest_open not in text:
    raise SystemExit('generated Cocoon manifest contract changed')
if 'android.permission.INTERNET' not in text:
    text = text.replace(
        manifest_open,
        manifest_open + '\n    <uses-permission android:name="android.permission.INTERNET" />',
        1,
    )
if 'android:label="cocoonmate"' not in text:
    raise SystemExit('generated Cocoon label contract changed')
text = text.replace('android:label="cocoonmate"', 'android:label="CocoonMate"', 1)
if 'android:icon="@mipmap/ic_launcher"' not in text:
    raise SystemExit('generated launcher icon contract changed')
text = text.replace(
    'android:icon="@mipmap/ic_launcher"',
    'android:icon="@mipmap/cocoon_launcher" android:roundIcon="@mipmap/cocoon_launcher"',
    1,
)
manifest_path.write_text(text)

gradle_text = gradle_path.read_text()
compile_options = '    compileOptions {\n'
if compile_options not in gradle_text:
    raise SystemExit('generated Cocoon compileOptions contract changed')
if 'isCoreLibraryDesugaringEnabled = true' not in gradle_text:
    gradle_text = gradle_text.replace(
        compile_options,
        compile_options + '        isCoreLibraryDesugaringEnabled = true\n',
        1,
    )
desugaring_dependency = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")'
if desugaring_dependency not in gradle_text:
    gradle_text = gradle_text.rstrip() + (
        '\n\ndependencies {\n'
        '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n'
        '}\n'
    )
gradle_path.write_text(gradle_text)
PY

  local res="$app_dir/android/app/src/main/res"
  mkdir -p \
    "$res/drawable" \
    "$res/mipmap-anydpi" \
    "$res/mipmap-anydpi-v26" \
    "$res/mipmap-anydpi-v33" \
    "$res/values" \
    "$res/values-v31"

  cat > "$res/values/cocoon_colors.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="cocoon_canvas">#FFF8F2</color>
    <color name="cocoon_coral">#A8434D</color>
</resources>
XML

  # The three separated forms read as a protected inner cocoon at launcher,
  # splash, monochrome and notification sizes without using fetal or heart
  # imagery. Keep the artwork inside the adaptive-icon safe zone.
  cat > "$res/drawable/cocoon_launcher_foreground.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFAF6"
        android:pathData="M50,18C31,20 20,34 20,54C20,74 31,88 50,90C40,79 35,67 35,54C35,41 40,29 50,18Z" />
    <path
        android:fillColor="#FFFFFAF6"
        android:pathData="M58,18C77,20 88,34 88,54C88,74 77,88 58,90C68,79 73,67 73,54C73,41 68,29 58,18Z" />
    <path
        android:fillColor="#FFF0EAF7"
        android:pathData="M54,35C45,43 45,65 54,73C63,65 63,43 54,35Z" />
</vector>
XML

  cat > "$res/drawable/cocoon_launcher_monochrome.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M50,18C31,20 20,34 20,54C20,74 31,88 50,90C40,79 35,67 35,54C35,41 40,29 50,18Z" />
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M58,18C77,20 88,34 88,54C88,74 77,88 58,90C68,79 73,67 73,54C73,41 68,29 58,18Z" />
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M54,35C45,43 45,65 54,73C63,65 63,43 54,35Z" />
</vector>
XML

  cat > "$res/mipmap-anydpi/cocoon_launcher.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFA8434D"
        android:pathData="M54,3A51,51 0,1 1,54 105A51,51 0,1 1,54 3Z" />
    <path
        android:fillColor="#FFFFFAF6"
        android:pathData="M50,18C31,20 20,34 20,54C20,74 31,88 50,90C40,79 35,67 35,54C35,41 40,29 50,18Z" />
    <path
        android:fillColor="#FFFFFAF6"
        android:pathData="M58,18C77,20 88,34 88,54C88,74 77,88 58,90C68,79 73,67 73,54C73,41 68,29 58,18Z" />
    <path
        android:fillColor="#FFF0EAF7"
        android:pathData="M54,35C45,43 45,65 54,73C63,65 63,43 54,35Z" />
</vector>
XML

  cat > "$res/mipmap-anydpi-v26/cocoon_launcher.xml" <<'XML'
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/cocoon_coral" />
    <foreground android:drawable="@drawable/cocoon_launcher_foreground" />
</adaptive-icon>
XML

  cat > "$res/mipmap-anydpi-v33/cocoon_launcher.xml" <<'XML'
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/cocoon_coral" />
    <foreground android:drawable="@drawable/cocoon_launcher_foreground" />
    <monochrome android:drawable="@drawable/cocoon_launcher_monochrome" />
</adaptive-icon>
XML

  # White-only small silhouette suitable for Android notification rendering.
  cat > "$res/drawable/cocoon_notification.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M50,18C31,20 20,34 20,54C20,74 31,88 50,90C40,79 35,67 35,54C35,41 40,29 50,18ZM58,18C77,20 88,34 88,54C88,74 77,88 58,90C68,79 73,67 73,54C73,41 68,29 58,18ZM54,35C45,43 45,65 54,73C63,65 63,43 54,35Z" />
</vector>
XML

  cat > "$res/drawable/cocoon_splash_mark.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFA8434D"
        android:pathData="M50,18C31,20 20,34 20,54C20,74 31,88 50,90C40,79 35,67 35,54C35,41 40,29 50,18ZM58,18C77,20 88,34 88,54C88,74 77,88 58,90C68,79 73,67 73,54C73,41 68,29 58,18Z" />
    <path
        android:fillColor="#FF8765B4"
        android:pathData="M54,35C45,43 45,65 54,73C63,65 63,43 54,35Z" />
</vector>
XML

  cat > "$res/drawable/launch_background.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/cocoon_canvas" />
    <item android:drawable="@drawable/cocoon_splash_mark" android:gravity="center" />
</layer-list>
XML

  cat > "$res/values-v31/styles.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:forceDarkAllowed">false</item>
        <item name="android:windowSplashScreenBackground">@color/cocoon_canvas</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/cocoon_splash_mark</item>
        <item name="android:postSplashScreenTheme">@style/NormalTheme</item>
        <item name="android:windowLightStatusBar">true</item>
    </style>
</resources>
XML

  grep -Fq 'applicationId = "com.mylifemate.cocoonmate"' "$gradle" || \
    fail "Cocoon Android applicationId is not isolated."
  grep -Fq 'isCoreLibraryDesugaringEnabled = true' "$gradle" || \
    fail "Cocoon Android core library desugaring is not enabled."
  grep -Fq 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")' "$gradle" || \
    fail "Cocoon Android desugaring dependency is missing."
  grep -Fq 'android:label="CocoonMate"' "$manifest" || \
    fail "Cocoon Android display name is missing."
  grep -Fq 'android.permission.INTERNET' "$manifest" || \
    fail "Cocoon Android release network permission is missing."
  grep -Fq '@mipmap/cocoon_launcher' "$manifest" || \
    fail "Cocoon Android launcher identity is missing."
  grep -Fq '@drawable/cocoon_launcher_foreground' \
    "$res/mipmap-anydpi-v26/cocoon_launcher.xml" || \
    fail "Cocoon Android adaptive launcher foreground is missing."
  grep -Fq '<monochrome android:drawable="@drawable/cocoon_launcher_monochrome"' \
    "$res/mipmap-anydpi-v33/cocoon_launcher.xml" || \
    fail "Cocoon Android monochrome launcher identity is missing."
  [[ -s "$res/drawable/cocoon_notification.xml" ]] || \
    fail "Cocoon Android notification-safe icon is missing."
  grep -Fq '@drawable/cocoon_splash_mark' "$res/drawable/launch_background.xml" || \
    fail "Cocoon Android legacy splash identity is missing."
  grep -Fq 'android:windowSplashScreenAnimatedIcon' "$res/values-v31/styles.xml" || \
    fail "Cocoon Android 12 splash identity is missing."
  if grep -R -Fq '#B75D88' "$res" || \
      grep -R -Fq 'M12,21.35l-1.45,-1.32' "$res"; then
    fail "Deprecated heart launcher artwork is still present."
  fi
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
