from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

screen_path = ROOT / 'wellmate/lib/screens/women_calendar/women_calendar_screen.dart'
text = screen_path.read_text(encoding='utf-8')
text = text.replace('_dateKey(', '_episodeDateKey(')
marker = '  void _replaceEpisodeLocally(\n'
helper = """  String _episodeDateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

"""
if helper not in text:
    if marker not in text:
        raise SystemExit('episode local helper marker missing')
    text = text.replace(marker, helper + marker, 1)
screen_path.write_text(text, encoding='utf-8')

native_path = ROOT / 'packages/lifemate_client/lib/src/durable_lifemate_api_client.dart'
native = native_path.read_text(encoding='utf-8')
old_native = """  LifeMateOfflineNamespace? get activeOfflineNamespace =>
      _activeSharedRuntime()?.namespace;
"""
new_native = """  LifeMateLocalNamespace? get activeOfflineNamespace {
    final namespace = _activeSharedRuntime()?.namespace;
    if (namespace == null) return null;
    return LifeMateLocalNamespace(
      environmentId: namespace.environmentId,
      accountId: namespace.accountId,
      personId: namespace.personId,
    );
  }
"""
if old_native in native:
    native = native.replace(old_native, new_native, 1)
elif new_native not in native:
    raise SystemExit('native activeOfflineNamespace marker missing')
native_path.write_text(native, encoding='utf-8')

web_path = ROOT / 'packages/lifemate_client/lib/src/durable_lifemate_api_client_web.dart'
web = web_path.read_text(encoding='utf-8')
web = web.replace(
    '  LifeMateOfflineNamespace? get activeOfflineNamespace => null;\n',
    '  LifeMateLocalNamespace? get activeOfflineNamespace => null;\n',
)
if 'LifeMateLocalNamespace? get activeOfflineNamespace => null;' not in web:
    raise SystemExit('web activeOfflineNamespace marker missing')
web_path.write_text(web, encoding='utf-8')
