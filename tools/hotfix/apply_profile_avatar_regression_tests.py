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


replace_once(
    "wellmate/test/ui_regression_test.dart",
    '''    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
    expect(
      avatar.backgroundImage,
      isA<AssetImage>().having(
        (image) => image.assetName,
        'assetName',
        'assets/images/mother_avatar.png',
      ),
    );
''',
    '''    expect(find.byType(LifeMateProfileAvatar), findsWidgets);
    final avatar = tester.widget<LifeMateProfileAvatar>(
      find.byType(LifeMateProfileAvatar).first,
    );
    expect(
      LifeMateProfileAvatars.normalize(avatar.avatarKey),
      LifeMateProfileAvatars.defaultKey,
    );
    expect(find.image(const AssetImage('assets/images/mother_avatar.png')), findsNothing);
''',
)

replace_once(
    "supabase/functions/lifemate-api/profile.ts",
    '''      await tx`
        insert into lifemate.audit_logs
''',
    '''      // Privacy invariant: metadata_json, null; no profile or avatar values.
      await tx`
        insert into lifemate.audit_logs
''',
)
