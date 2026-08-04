from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"Expected snippet not found in {path}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


path = "wellmate/lib/screens/profile/profile_screen.dart"
wrong_method = '''  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditableProfileScreen()),
    );
    if (!mounted) return;
    setState(() {
      _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
    });
  }

'''

# The materialization patch originally used a generic build-method anchor. Remove
# the method if it landed in the top-level StatelessWidget and then add it to the
# state object that owns `_currentUser`.
target = ROOT / path
text = target.read_text(encoding="utf-8")
profile_class = text.find("class ProfileScreen extends StatelessWidget")
identity_class = text.find("class _CurrentUserIdentity extends StatefulWidget")
wrong_index = text.find(wrong_method)
if wrong_index >= 0 and profile_class <= wrong_index < identity_class:
    text = text[:wrong_index] + text[wrong_index + len(wrong_method):]
    target.write_text(text, encoding="utf-8")

replace_once(
    path,
    '''  @override
  void initState() {
    super.initState();
    _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
''',
    '''  @override
  void initState() {
    super.initState();
    _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditableProfileScreen()),
    );
    if (!mounted) return;
    setState(() {
      _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
''',
)

# Existing installed clients and candidate smoke scripts may omit avatarKey.
# Preserve the current value for those requests while validating every explicit
# key against the same allow-list used by the database constraint.
profile_path = "supabase/functions/lifemate-api/profile.ts"
replace_once(
    profile_path,
    "  avatarKey: string;\n",
    "  avatarKey: string | null;\n",
)
replace_once(
    profile_path,
    "    avatarKey: requiredAvatarKey(body.avatarKey),\n",
    "    avatarKey: optionalAvatarKey(body.avatarKey),\n",
)
replace_once(
    profile_path,
    "                avatar_key = ${patch.avatarKey},\n",
    "                avatar_key = coalesce(${patch.avatarKey}, avatar_key),\n",
)
replace_once(
    profile_path,
    "                avatar_key = ${patch.avatarKey},\n",
    "                avatar_key = coalesce(${patch.avatarKey}, avatar_key),\n",
)
replace_once(
    profile_path,
    '''function requiredAvatarKey(value: unknown): string {
  const normalized = normalizeOptional(value);
  if (normalized == null || !allowedAvatarKeys.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_avatar_key",
      "avatarKey is not supported.",
    );
  }
  return normalized;
}
''',
    '''function optionalAvatarKey(value: unknown): string | null {
  const normalized = normalizeOptional(value);
  if (normalized == null) return null;
  if (!allowedAvatarKeys.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_avatar_key",
      "avatarKey is not supported.",
    );
  }
  return normalized;
}
''',
)

profile_test_path = "supabase/functions/lifemate-api/profile_test.ts"
replace_once(
    profile_test_path,
    '''Deno.test("profile patch permits clearing the optional phone number", () => {
  assertEquals(
    normalizeProfilePatch({
      version: 1,
      displayName: "Owner",
      phoneNumber: "",
      locale: "en-US",
      timeZone: "Europe/Berlin",
      avatarKey: "caregiver_teal",
    }).phoneNumber,
    null,
  );
});
''',
    '''Deno.test("profile patch permits legacy clients and clearing the optional phone", () => {
  const patch = normalizeProfilePatch({
    version: 1,
    displayName: "Owner",
    phoneNumber: "",
    locale: "en-US",
    timeZone: "Europe/Berlin",
  });
  assertEquals(patch.phoneNumber, null);
  assertEquals(patch.avatarKey, null);
});
''',
)
