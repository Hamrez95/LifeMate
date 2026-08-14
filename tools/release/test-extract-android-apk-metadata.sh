#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
extractor="$repo_root/tools/release/extract-android-apk-metadata.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

touch "$tmp/app.apk"
cat > "$tmp/aapt" <<'AAPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" != dump || "$2" != badging ]]; then exit 2; fi
cat <<'OUTPUT'
package: name='com.lifemate.wellmate' versionCode='123456' versionName='0.9.2' compileSdkVersion='36' compileSdkVersionCodename='16'
sdkVersion:'24'
targetSdkVersion:'36'
application-label:'WellMate'
OUTPUT
AAPT
chmod +x "$tmp/aapt"

result="$(bash "$extractor" "$tmp/app.apk" "$tmp/aapt" com.lifemate.wellmate)"
jq -e '
  .packageId == "com.lifemate.wellmate" and
  .minSdk == 24 and
  .targetSdk == 36 and
  .maxSdk == null and
  .versionCode == 123456 and
  .versionName == "0.9.2"
' <<<"$result" >/dev/null

if bash "$extractor" "$tmp/app.apk" "$tmp/aapt" com.lifemate.caremate >/dev/null 2>&1; then
  echo 'Extractor unexpectedly accepted the wrong package id.' >&2
  exit 1
fi

echo 'Android APK metadata extractor tests passed.'
