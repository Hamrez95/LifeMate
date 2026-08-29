import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

class WomenCompanionPrivacyScreen extends StatefulWidget {
  const WomenCompanionPrivacyScreen({super.key, required this.relationship});

  final Map<String, dynamic> relationship;

  @override
  State<WomenCompanionPrivacyScreen> createState() =>
      _WomenCompanionPrivacyScreenState();
}

class _WomenCompanionPrivacyScreenState
    extends State<WomenCompanionPrivacyScreen> {
  static const _keys = <String>[
    'viewPeriodTiming',
    'viewPhaseSummary',
    'viewSharedWellbeing',
    'receiveMoodSupportNotifications',
    'receivePhaseNotifications',
    'viewFertilityEstimate',
    'receiveFertilityNotifications',
    'viewCalendarDetail',
  ];
  static const _presentationTypes = <String>[
    'partner',
    'child_caring_for_parent',
    'parent_caring_for_dependent',
    'family',
    'trusted_caregiver',
    'unknown',
  ];

  bool _loading = true;
  bool _saving = false;
  bool _savingPresentation = false;
  String? _error;
  int _version = 0;
  Map<String, bool> _scopes = {for (final key in _keys) key: false};
  late final TextEditingController _caregiverAliasController;
  String _presentationType = 'unknown';
  String? _caregiverOfficialName;

  String get _id => widget.relationship['id'].toString();

  @override
  void initState() {
    super.initState();
    _caregiverAliasController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _caregiverAliasController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        context.read<LifeMateApiClient>().getWomenCompanionPrivacyScopes(),
        context.read<LifeMateApiClient>().getCareRelationships(),
      ]);
      final privacyRows = results[0] as List<Map<String, dynamic>>;
      final relationships = results[1] as List<Map<String, dynamic>>;
      final current = privacyRows
          .where((row) => row['relationshipId']?.toString() == _id)
          .cast<Map<String, dynamic>>()
          .firstOrNull;
      final relationship = relationships
          .where((row) => row['id']?.toString() == _id)
          .cast<Map<String, dynamic>>()
          .firstOrNull;
      if (!mounted) return;
      final source = current?['scopes'] as Map<String, dynamic>? ?? const {};
      final official = _text(relationship?['caregiverOfficialDisplayName']);
      final effective = _text(relationship?['caregiverDisplayName']);
      setState(() {
        _version = current?['version'] is int ? current!['version'] as int : 0;
        _scopes = {for (final key in _keys) key: source[key] == true};
        _presentationType = LifeMateRelationshipPresentationPolicy.fromRaw(
          relationship?['presentationType']?.toString(),
        ).storageValue;
        _caregiverOfficialName = official;
        _caregiverAliasController.text =
            effective != null && effective != official ? effective : '';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تنظیمات حریم خصوصی دریافت نشد.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await context
          .read<LifeMateApiClient>()
          .updateWomenCompanionPrivacyScopes(
            relationshipId: _id,
            version: _version,
            scopes: _scopes,
          );
      if (!mounted) return;
      setState(
        () => _version = result['version'] is int
            ? result['version'] as int
            : _version + 1,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تنظیمات حریم خصوصی ذخیره شد.')),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'stale_companion_privacy_scopes') await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تنظیمات ذخیره نشد؛ اطلاعات تازه شد.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePresentation() async {
    if (_savingPresentation) return;
    setState(() => _savingPresentation = true);
    final api = LifeMateRelationshipPresentationApi.fromEnvironment();
    try {
      await api.update(
        relationshipId: _id,
        relationshipType: _presentationType,
        displayName: _caregiverAliasController.text,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نام و نوع رابطه ذخیره شد.')),
      );
    } on LifeMateApiException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نام یا نوع رابطه ذخیره نشد.')),
      );
    } finally {
      api.close();
      if (mounted) setState(() => _savingPresentation = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حریم خصوصی همدم')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'هر مورد فقط برای همین رابطه اعمال می‌شود. اطلاعات حساس و fertility پیش‌فرض خاموش‌اند؛ یادداشت خصوصی هرگز قابل اشتراک نیست.',
                    style: TextStyle(height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  _RelationshipPresentationCard(
                    officialName: _caregiverOfficialName,
                    controller: _caregiverAliasController,
                    presentationType: _presentationType,
                    types: _presentationTypes,
                    saving: _savingPresentation,
                    onTypeChanged: (value) =>
                        setState(() => _presentationType = value),
                    onSave: _savePresentation,
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 6),
                  for (final entry in _labels.entries)
                    SwitchListTile.adaptive(
                      key: ValueKey('companion-privacy-${entry.key}'),
                      title: Text(entry.value.$1),
                      subtitle: Text(entry.value.$2),
                      value: _scopes[entry.key] ?? false,
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _scopes[entry.key] = value,
                            ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('disable-all-companion-privacy'),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _scopes = {
                              for (final key in _keys) key: false,
                            };
                          }),
                    icon: const Icon(Icons.visibility_off_rounded),
                    label: const Text('قطع همه دسترسی‌های این بخش'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('save-companion-privacy'),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'در حال ذخیره…' : 'ذخیره دسترسی‌ها'),
                  ),
                ],
              ),
      );

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _RelationshipPresentationCard extends StatelessWidget {
  const _RelationshipPresentationCard({
    required this.officialName,
    required this.controller,
    required this.presentationType,
    required this.types,
    required this.saving,
    required this.onTypeChanged,
    required this.onSave,
  });

  final String? officialName;
  final TextEditingController controller;
  final String presentationType;
  final List<String> types;
  final bool saving;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'نام و نوع رابطه',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                'این بخش فقط روی نحوه نمایش و لحن اثر دارد و هیچ دسترسی جدیدی فعال نمی‌کند.',
                style: TextStyle(height: 1.5, fontSize: 12),
              ),
              if (officialName != null) ...[
                const SizedBox(height: 8),
                Text('نام رسمی: $officialName'),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('owner-relationship-presentation-type'),
                initialValue: presentationType,
                decoration: const InputDecoration(labelText: 'نوع رابطه'),
                items: types
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(
                          LifeMateRelationshipPresentationPolicy.fromRaw(value)
                              .relationshipLabel(isPersian: true),
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) onTypeChanged(value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('owner-caregiver-display-name'),
                controller: controller,
                enabled: !saving,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'نامی که من برای این فرد می‌بینم',
                  hintText: 'مثلاً همسرم یا علی جان',
                  helperText: 'خالی بگذار تا نام رسمی نمایش داده شود.',
                ),
              ),
              FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.badge_outlined),
                label: Text(saving ? 'در حال ذخیره…' : 'ذخیره نام و رابطه'),
              ),
            ],
          ),
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

const _labels = <String, (String, String)>{
  'viewPeriodTiming': (
    'شروع/روزهای دوره',
    'روزهای دوره را می‌بیند، نه یادداشت خصوصی.',
  ),
  'viewPhaseSummary': (
    'خلاصه تقریبی phase',
    'وضعیت تقریبی است و قطعیت پزشکی ندارد.',
  ),
  'viewSharedWellbeing': (
    'mood و energy اشتراک‌داده‌شده',
    'فقط فیلدهایی که خودت share کرده‌ای.',
  ),
  'receiveMoodSupportNotifications': (
    'اعلان حمایت از mood',
    'پیش‌فرض خاموش؛ بدون تشخیص یا private note.',
  ),
  'receivePhaseNotifications': (
    'اعلان‌های phase',
    'پیش‌فرض خاموش و با wording تقریبی.',
  ),
  'viewFertilityEstimate': (
    'بازه تخمینی fertility',
    'حساس؛ فقط تخمین و پیش‌فرض خاموش.',
  ),
  'receiveFertilityNotifications': (
    'اعلان fertility',
    'حساس؛ مستقل و پیش‌فرض خاموش.',
  ),
  'viewCalendarDetail': (
    'جزئیات تقویم',
    'جزئیات مجاز تقویم؛ یادداشت خصوصی همچنان مخفی است.',
  ),
};
