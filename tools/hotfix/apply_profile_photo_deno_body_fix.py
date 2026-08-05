from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "supabase/functions/lifemate-api/profile_photo.ts"

value = PATH.read_text(encoding="utf-8")

old_validation = """    const validated = validateProfilePhoto(bytes, rawContentType);
    await ensurePrivateBucket();
"""
new_validation = """    const validated = validateProfilePhoto(bytes, rawContentType);
    const uploadBytes = new Uint8Array(bytes.length);
    uploadBytes.set(bytes);
    await ensurePrivateBucket();
"""

if new_validation not in value:
    if old_validation not in value:
        raise RuntimeError("Profile-photo upload validation marker was not found.")
    value = value.replace(old_validation, new_validation, 1)

old_body = """      body: bytes,
"""
new_body = """      body: uploadBytes.buffer,
"""

if new_body not in value:
    if old_body not in value:
        raise RuntimeError("Profile-photo upload body marker was not found.")
    value = value.replace(old_body, new_body, 1)

PATH.write_text(value, encoding="utf-8")
print("Profile-photo upload uses a Deno-compatible ArrayBuffer body.")
