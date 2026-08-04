from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/flutter.yml"


def replace_once(old: str, new: str) -> None:
    text = WORKFLOW.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            return
        raise SystemExit("Expected Flutter workflow checkpoint snippet was not found")
    WORKFLOW.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    '''          if [[ "${{ github.event_name }}" == "workflow_dispatch" && "${{ inputs.build_android }}" == "true" ]]; then
            should_build=true
          fi
''',
    '''          if [[ "${{ github.event_name }}" == "workflow_dispatch" && "${{ inputs.build_android }}" == "true" ]]; then
            should_build=true
          elif [[ "${{ github.event_name }}" == "pull_request" \
            && "${{ github.event.pull_request.head.ref }}" == "feat/women-calendar-care-access-notifications" ]]; then
            # Internal Device-QA only; never a Stable or RC publication.
            should_build=true
          fi
''',
)

replace_once(
    '''            --dart-define="ENABLE_GOOGLE_AUTH=$ENABLE_GOOGLE_AUTH"
          )
          (cd wellmate && flutter build apk "${build_args[@]}")
          (cd caremate && flutter build apk "${build_args[@]}")
''',
    '''            --dart-define="ENABLE_GOOGLE_AUTH=$ENABLE_GOOGLE_AUTH"
            --dart-define="ENABLE_WOMEN_CALENDAR_PILOT=true"
          )
          grep -q '^version: 0.9.0-internal.5+16$' wellmate/pubspec.yaml
          grep -q '^version: 0.9.0-internal.5+16$' caremate/pubspec.yaml
          (cd wellmate && flutter build apk "${build_args[@]}")
          (cd caremate && flutter build apk "${build_args[@]}")
          cp wellmate/build/app/outputs/flutter-apk/app-release.apk \
            wellmate/build/app/outputs/flutter-apk/WellMate-0.9.0-internal.5-device-qa.apk
          cp caremate/build/app/outputs/flutter-apk/app-release.apk \
            caremate/build/app/outputs/flutter-apk/CareMate-0.9.0-internal.5-device-qa.apk
          cat > /tmp/LIFEMATE-DEVICE-QA-NOTICE.txt <<'EOF'
LifeMate 0.9.0-internal.5+16
Internal Device-QA only. Not Stable. Not RC. Not for public distribution.
Candidate API only. Google authentication disabled. Women calendar pilot enabled.
Physical notification QA remains required for permission, exact alarms,
lock-screen privacy, reboot, timezone change and app-update resynchronization.
EOF
''',
)

replace_once(
    '''          name: lifemate-android-beta-apks
          path: |
            wellmate/build/app/outputs/flutter-apk/app-release*.apk
            caremate/build/app/outputs/flutter-apk/app-release*.apk
            /tmp/lifemate-apk-inspection/**
''',
    '''          name: lifemate-0.9.0-internal.5-device-qa-apks
          path: |
            wellmate/build/app/outputs/flutter-apk/WellMate-0.9.0-internal.5-device-qa.apk
            caremate/build/app/outputs/flutter-apk/CareMate-0.9.0-internal.5-device-qa.apk
            /tmp/LIFEMATE-DEVICE-QA-NOTICE.txt
            /tmp/lifemate-apk-inspection/**
''',
)

subprocess.run(
    ["git", "add", "--", ".github/workflows/flutter.yml"],
    cwd=ROOT,
    check=True,
)
print("Flutter PR checkpoint now builds internal Device-QA APK artifacts.")
