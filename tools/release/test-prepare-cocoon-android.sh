#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

mkdir -p "$fixture/tools/release" "$fixture/cocoonmate/test" "$fixture/bin"
cp "$source_root/tools/release/prepare-cocoon-android.sh" \
  "$fixture/tools/release/prepare-cocoon-android.sh"
printf 'name: cocoonmate\n' > "$fixture/cocoonmate/pubspec.yaml"

cat > "$fixture/bin/flutter" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" = create ]]
mkdir -p android/app/src/main/res/drawable android/app/src/main/res/values
cat > android/app/src/main/AndroidManifest.xml <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="cocoonmate" android:icon="@mipmap/ic_launcher" />
</manifest>
XML
cat > android/app/build.gradle.kts <<'KTS'
android {
    namespace = "com.mylifemate.cocoonmate"
    compileOptions {
    }
    defaultConfig {
        applicationId = "com.mylifemate.cocoonmate"
    }
}
KTS
cat > android/app/src/main/res/values/styles.xml <<'XML'
<resources>
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar" />
</resources>
XML
SH
chmod +x "$fixture/bin/flutter"

PATH="$fixture/bin:$PATH" \
LIFEMATE_RELEASE_ENVIRONMENT=ci \
SUPABASE_URL=https://cocoon-ci.invalid \
LIFEMATE_API_BASE_URL=https://cocoon-ci.invalid/functions/v1/lifemate-api \
  bash "$fixture/tools/release/prepare-cocoon-android.sh" prepare

manifest="$fixture/cocoonmate/android/app/src/main/AndroidManifest.xml"
res="$fixture/cocoonmate/android/app/src/main/res"

grep -Fq 'android:icon="@mipmap/cocoon_launcher"' "$manifest"
grep -Fq 'android:roundIcon="@mipmap/cocoon_launcher"' "$manifest"
grep -Fq '@drawable/cocoon_launcher_foreground' \
  "$res/mipmap-anydpi-v26/cocoon_launcher.xml"
grep -Fq '@drawable/cocoon_launcher_monochrome' \
  "$res/mipmap-anydpi-v33/cocoon_launcher.xml"
grep -Fq '@drawable/cocoon_splash_mark' "$res/drawable/launch_background.xml"
grep -Fq 'android:windowSplashScreenAnimatedIcon' "$res/values-v31/styles.xml"
test -s "$res/drawable/cocoon_notification.xml"

! grep -R -Fq '#B75D88' "$res"
! grep -R -Fq 'M12,21.35l-1.45,-1.32' "$res"

"${PYTHON:-python3}" - "$res" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

resource_root = Path(sys.argv[1])
xml_files = sorted(resource_root.rglob('*.xml'))
assert xml_files, 'expected generated Android resources'
for path in xml_files:
    ET.parse(path)
PY

echo "Cocoon Android identity generation test passed."
