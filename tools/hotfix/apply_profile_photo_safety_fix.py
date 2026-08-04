from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace(path: str, old: str, new: str) -> None:
    target = ROOT / path
    value = target.read_text(encoding="utf-8")
    if new in value:
        return
    if old not in value:
        raise RuntimeError(f"Profile-photo safety marker missing in {path}")
    target.write_text(value.replace(old, new, 1), encoding="utf-8")


replace(
    "supabase/functions/lifemate-api/profile_photo.ts",
    "const headers = (contentType?: string): HeadersInit => ({",
    "const headers = (contentType?: string): Record<string, string> => ({",
)
replace(
    "supabase/functions/lifemate-api/profile_photo.ts",
    """    return signed.startsWith("http")
      ? signed
      : `${supabaseUrl.replace(/\\/+$/, "")}${signed.startsWith("/") ? "" : "/"}${signed}`;""",
    """    if (signed.startsWith("http")) return signed;
    if (signed.startsWith("/storage/v1/")) {
      return `${supabaseUrl.replace(/\\/+$/, "")}${signed}`;
    }
    return `${storageRoot}${signed.startsWith("/") ? "" : "/"}${signed}`;""",
)
replace(
    "packages/lifemate_client/lib/src/profile_avatar.dart",
    """              ? Image.network(
                  normalizedPhotoUrl,""",
    """              ? Image.network(
                  normalizedPhotoUrl!,""",
)

migration = ROOT / "supabase/migrations/20260805023000_add_profile_photo_path.sql"
value = migration.read_text(encoding="utf-8")
value = value.replace(r"\\.(jpg|png|webp)", "[.](jpg|png|webp)")
value = value.replace(r"\.(jpg|png|webp)", "[.](jpg|png|webp)")
migration.write_text(value, encoding="utf-8")

print("Profile-photo generated adapters hardened.")
