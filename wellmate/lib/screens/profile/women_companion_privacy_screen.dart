import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

class WomenCompanionPrivacyScreen extends StatefulWidget {
  const WomenCompanionPrivacyScreen({super.key, required this.relationship});
  final Map<String, dynamic> relationship;
  @override State<WomenCompanionPrivacyScreen> createState() => _WomenCompanionPrivacyScreenState();
}
class _WomenCompanionPrivacyScreenState extends State<WomenCompanionPrivacyScreen> {
  static const _keys = <String>[
    'viewPeriodTiming', 'viewPhaseSummary', 'viewSharedWellbeing',
    'receiveMoodSupportNotifications', 'receivePhaseNotifications',
    'viewFertilityEstimate', 'receiveFertilityNotifications', 'viewCalendarDetail',
  ];
  bool _loading = true, _saving = false;
  String? _error;
  int _version = 0;
  Map<String, bool> _scopes = {for (final key in _keys) key: false};
  String get _id => widget.relationship['id'].toString();
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await context.read<LifeMateApiClient>().getWomenCompanionPrivacyScopes();
      final current = rows.where((row) => row['relationshipId']?.toString() == _id).cast<Map<String, dynamic>>().firstOrNull;
      if (!mounted) return;
      final source = current?['scopes'] as Map<String, dynamic>? ?? const {};
      setState(() {
        _version = current?['version'] is int ? current!['version'] as int : 0;
        _scopes = {for (final key in _keys) key: source[key] == true};
      });
    } catch (_) { if (mounted) setState(() => _error = 'تنظیمات حریم خصوصی دریافت نشد.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await context.read<LifeMateApiClient>().updateWomenCompanionPrivacyScopes(
        relationshipId: _id, version: _version, scopes: _scopes);
      if (!mounted) return;
      setState(() => _version = result['version'] is int ? result['version'] as int : _version + 1);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات حریم خصوصی ذخیره شد.')));
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'stale_companion_privacy_scopes') await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تنظیمات ذخیره نشد؛ اطلاعات تازه شد.')));
    } finally { if (mounted) setState(() => _saving = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('حریم خصوصی همدم')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
      padding: const EdgeInsets.all(16), children: [
        const Text('هر مورد فقط برای همین رابطه اعمال می‌شود. اطلاعات حساس و fertility پیش‌فرض خاموش‌اند؛ یادداشت خصوصی هرگز قابل اشتراک نیست.', style: TextStyle(height: 1.6)),
        const SizedBox(height: 14),
        for (final entry in _labels.entries) SwitchListTile.adaptive(
          key: ValueKey('companion-privacy-${entry.key}'),
          title: Text(entry.value.$1), subtitle: Text(entry.value.$2),
          value: _scopes[entry.key] ?? false, onChanged: _saving ? null : (value) => setState(() => _scopes[entry.key] = value)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('disable-all-companion-privacy'),
          onPressed: _saving
              ? null
              : () => setState(() {
                    _scopes = {for (final key in _keys) key: false};
                  }),
          icon: const Icon(Icons.visibility_off_rounded),
          label: const Text('قطع همه دسترسی‌های این بخش'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(key: const ValueKey('save-companion-privacy'), onPressed: _saving ? null : _save, icon: const Icon(Icons.save_rounded), label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره')),
      ]),
  );
}
extension _FirstOrNull<T> on Iterable<T> { T? get firstOrNull => isEmpty ? null : first; }
const _labels = <String, (String, String)>{
  'viewPeriodTiming': ('شروع/روزهای دوره', 'روزهای دوره را می‌بیند، نه یادداشت خصوصی.'),
  'viewPhaseSummary': ('خلاصه تقریبی phase', 'وضعیت تقریبی است و قطعیت پزشکی ندارد.'),
  'viewSharedWellbeing': ('mood و energy اشتراک‌داده‌شده', 'فقط فیلدهایی که خودت share کرده‌ای.'),
  'receiveMoodSupportNotifications': ('اعلان حمایت از mood', 'پیش‌فرض خاموش؛ بدون تشخیص یا private note.'),
  'receivePhaseNotifications': ('اعلان‌های phase', 'پیش‌فرض خاموش و با wording تقریبی.'),
  'viewFertilityEstimate': ('بازه تخمینی fertility', 'حساس؛ فقط تخمین و پیش‌فرض خاموش.'),
  'receiveFertilityNotifications': ('اعلان fertility', 'حساس؛ مستقل و پیش‌فرض خاموش.'),
  'viewCalendarDetail': ('جزئیات تقویم', 'جزئیات مجاز تقویم؛ یادداشت خصوصی همچنان مخفی است.'),
};