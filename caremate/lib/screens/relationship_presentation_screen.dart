import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import 'feature_preview_screen.dart';

class CareMateRelationshipPresentationScreen extends StatefulWidget {
  const CareMateRelationshipPresentationScreen({super.key});

  @override
  State<CareMateRelationshipPresentationScreen> createState() =>
      _CareMateRelationshipPresentationScreenState();
}

class _CareMateRelationshipPresentationScreenState
    extends State<CareMateRelationshipPresentationScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await context.read<LifeMateApiClient>().getCareRelationships();
    return rows
        .where(
          (row) =>
              row['status']?.toString().toLowerCase() == 'active' &&
              row['notificationPreferences'] is Map,
        )
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = LifeMateRuntimeLocale.isPersian;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(isPersian ? 'افراد و نام‌های نمایشی' : 'People and nicknames'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _RelationshipErrorState(onRetry: _refresh);
          }
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                _IntroCard(isPersian: isPersian),
                const SizedBox(height: 14),
                if (rows.isEmpty)
                  _EmptyRelationshipState(isPersian: isPersian)
                else
                  ...rows.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _RelationshipCard(
                        relationship: row,
                        onSaved: _refresh,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  key: const ValueKey('caremate-open-access-inventory'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => LifeMateCareAccessInventoryScreen(
                        apiClient: context.read<LifeMateApiClient>(),
                        role: LifeMateCareAccessRole.caregiver,
                        accent: AppColors.primaryBlue,
                        background: AppColors.background,
                        ink: AppColors.darkBlue,
                        onManage: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const CareMateFeaturePreviewScreen(
                              initialIndex: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(
                    isPersian
                        ? 'مشاهده دسترسی‌ها و رضایت‌ها'
                        : 'View access and consent',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.isPersian});

  final bool isPersian;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.people_alt_outlined, color: AppColors.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isPersian
                    ? 'نوع رابطه را صاحب WellMate هنگام دعوت مشخص می‌کند و در CareMate قابل تغییر نیست. تو فقط می‌توانی نامی را که برای آن فرد می‌بینی انتخاب کنی؛ این نام روی هیچ دسترسی یا رضایتی اثر ندارد.'
                    : 'The WellMate owner chooses the relationship type during invitation and it cannot be changed here. You can only choose the nickname you see; it never changes access or consent.',
                style: const TextStyle(height: 1.55),
              ),
            ),
          ],
        ),
      );
}

class _RelationshipCard extends StatefulWidget {
  const _RelationshipCard({
    required this.relationship,
    required this.onSaved,
  });

  final Map<String, dynamic> relationship;
  final Future<void> Function() onSaved;

  @override
  State<_RelationshipCard> createState() => _RelationshipCardState();
}

class _RelationshipCardState extends State<_RelationshipCard> {
  late final TextEditingController _displayNameController;
  late final String _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = LifeMateRelationshipPresentationPolicy.fromRaw(
      widget.relationship['relationshipType']?.toString() ??
          widget.relationship['presentationType']?.toString(),
    ).storageValue;
    final official = _text(widget.relationship['patientOfficialDisplayName']);
    final effective = _text(widget.relationship['patientDisplayName']);
    _displayNameController = TextEditingController(
      text: effective != null && effective != official ? effective : '',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final api = LifeMateRelationshipPresentationApi.fromEnvironment();
    try {
      await api.update(
        relationshipId: widget.relationship['id'].toString(),
        relationshipType: _type,
        displayName: _displayNameController.text,
      );
      await widget.onSaved();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: 'نام نمایشی ذخیره شد.',
              en: 'Nickname saved.',
            ),
          ),
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: 'ذخیره انجام نشد. دوباره تلاش کنید.',
              en: 'Changes were not saved. Try again.',
            ),
          ),
        ),
      );
      debugPrint('Relationship presentation save failed: ${error.code}');
    } finally {
      api.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = LifeMateRuntimeLocale.isPersian;
    final official =
        _text(widget.relationship['patientOfficialDisplayName']) ??
            _text(widget.relationship['patientDisplayName']) ??
            (isPersian ? 'فرد تحت مراقبت' : 'Person under care');
    final policy = LifeMateRelationshipPresentationPolicy.fromRaw(_type);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryBlue.withValues(alpha: .10),
                  child: const Icon(Icons.person_outline_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(widget.relationship['patientDisplayName']) ?? official,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        isPersian
                            ? 'نام رسمی: $official'
                            : 'Official name: $official',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    isPersian ? 'نوع رابطه: ' : 'Relationship: ',
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                  Text(
                    policy.relationshipLabel(isPersian: isPersian),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: ValueKey(
                'relationship-display-name-${widget.relationship['id']}',
              ),
              controller: _displayNameController,
              enabled: !_saving,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: isPersian
                    ? 'نامی که من می‌بینم'
                    : 'Display name I use',
                hintText: isPersian
                    ? 'مثلاً پسرم یا حمید عزیزم'
                    : 'For example, my son or dear Hamid',
                helperText: isPersian
                    ? 'خالی بگذار تا نام رسمی نمایش داده شود.'
                    : 'Leave blank to use the official name.',
              ),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(isPersian ? 'ذخیره نام' : 'Save nickname'),
            ),
          ],
        ),
      ),
    );
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _EmptyRelationshipState extends StatelessWidget {
  const _EmptyRelationshipState({required this.isPersian});

  final bool isPersian;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            isPersian
                ? 'هنوز رابطه مراقبتی فعالی برای تنظیم وجود ندارد.'
                : 'There is no active care relationship to configure yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _RelationshipErrorState extends StatelessWidget {
  const _RelationshipErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(
            LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Retry'),
          ),
        ),
      );
}
