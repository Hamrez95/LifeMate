from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "packages/lifemate_client/lib/src/profile_avatar.dart"

value = PATH.read_text(encoding="utf-8")
value = value.replace("normalizedPhotoUrl!,", "normalizedPhotoUrl,")
value = value.replace(
    "errorBuilder: (_, _, _) =>",
    "errorBuilder: (context, error, stackTrace) =>",
)
PATH.write_text(value, encoding="utf-8")

print("Profile avatar analyzer errors resolved.")
