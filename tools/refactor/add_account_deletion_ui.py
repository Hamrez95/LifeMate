from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


wellmate = Path('wellmate/lib/screens/profile/profile_screen.dart')
well_anchor = '''              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withOpacity(0.12),
'''
well_insert = '''              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: OutlinedButton.icon(
                  key: const ValueKey('wellmate-account-deletion'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withOpacity(0.28),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    'حذف حساب و داده‌های شخصی',
                    style: TextStyle(
                      fontFamily: mainFont,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () => showLifeMateAccountDeletionDialog(
                    context,
                    apiClient: context.read<LifeMateApiClient>(),
                    fontFamily: mainFont,
                  ),
                ),
              ),
''' + well_anchor
replace_once(wellmate, well_anchor, well_insert, 'wellmate deletion action')

caremate = Path('caremate/lib/screens/profile_screen.dart')
care_anchor = '''                          const _MenuDivider(),
                          _ProfileMenuTile(
                            key: const ValueKey<String>(
                              'caremate-profile-sign-out',
                            ),
'''
care_insert = '''                          const _MenuDivider(),
                          _ProfileMenuTile(
                            key: const ValueKey<String>(
                              'caremate-account-deletion',
                            ),
                            icon: Icons.delete_forever_outlined,
                            iconColor: Colors.redAccent,
                            label: 'حذف حساب و داده‌های شخصی',
                            mainFont: mainFont,
                            subtitle: 'لغو دسترسی‌ها و شروع حذف/ناشناس‌سازی امن',
                            destructive: true,
                            showChevron: false,
                            onTap: () => showLifeMateAccountDeletionDialog(
                              context,
                              apiClient: context.read<LifeMateApiClient>(),
                              fontFamily: mainFont,
                            ),
                          ),
                          const _MenuDivider(),
                          _ProfileMenuTile(
                            key: const ValueKey<String>(
                              'caremate-profile-sign-out',
                            ),
'''
replace_once(caremate, care_anchor, care_insert, 'caremate deletion action')
print('account deletion actions added to WellMate and CareMate')
