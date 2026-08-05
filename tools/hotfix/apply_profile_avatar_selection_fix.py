from pathlib import Path
import runpy

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

# Exercise the real profile editors, not only the shared picker. Their fake API
# clients must follow the production contract and prove the selected key is sent.
for test_path, picker_key, selected_key, profile_id, user_id in [
    (
        "wellmate/test/editable_profile_screen_test.dart",
        "profile-avatar-person_purple",
        "person_purple",
        "profile-1",
        "user-1",
    ),
    (
        "caremate/test/editable_profile_screen_test.dart",
        "profile-avatar-caregiver_teal",
        "caregiver_teal",
        "profile-2",
        "user-2",
    ),
]:
    replace_once(
        test_path,
        "  String? savedTimeZone;\n",
        "  String? savedTimeZone;\n  String? savedAvatarKey;\n",
    )
    replace_once(
        test_path,
        "        'timeZone': 'Asia/Tehran',\n        'version':",
        "        'timeZone': 'Asia/Tehran',\n"
        "        'avatarKey': 'person_blue',\n"
        "        'version':",
    )
    replace_once(
        test_path,
        "    required String timeZone,\n  }) async {\n",
        "    required String timeZone,\n"
        "    required String avatarKey,\n"
        "  }) async {\n",
    )
    replace_once(
        test_path,
        "    savedTimeZone = timeZone;\n",
        "    savedTimeZone = timeZone;\n    savedAvatarKey = avatarKey;\n",
    )
    replace_once(
        test_path,
        "      'timeZone': timeZone.trim(),\n      'version': version + 1,\n",
        "      'timeZone': timeZone.trim(),\n"
        "      'avatarKey': avatarKey,\n"
        "      'version': version + 1,\n",
    )

    target = ROOT / test_path
    text = target.read_text(encoding="utf-8")
    save_anchor = "    final save = find.byKey("
    avatar_action = (
        "    await tester.tap(find.byKey(const ValueKey<String>('"
        + picker_key
        + "')));\n"
        "    await tester.pumpAndSettle();\n\n"
    )
    if avatar_action not in text:
        anchor_index = text.find(save_anchor)
        if anchor_index < 0:
            raise SystemExit(f"Save anchor not found in {test_path}")
        text = text[:anchor_index] + avatar_action + text[anchor_index:]
        target.write_text(text, encoding="utf-8")

    replace_once(
        test_path,
        "    expect(api.savedTimeZone, 'Europe/Berlin');\n",
        "    expect(api.savedTimeZone, 'Europe/Berlin');\n"
        f"    expect(api.savedAvatarKey, '{selected_key}');\n",
    )

runpy.run_path(
    str(ROOT / "tools/hotfix/apply_profile_avatar_regression_tests.py"),
    run_name="__main__",
)
