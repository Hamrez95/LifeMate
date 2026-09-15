import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

/// Person-owned, private documents collected from the Care Hub.
///
/// The screen never receives an object key or a file name. A short-lived URL is
/// requested only after the owner taps an item, keeping document access inside
/// the reviewed Health Record API boundary.
class HealthRecordScreen extends StatefulWidget {
  const HealthRecordScreen({super.key, this.personId});

  final String? personId;

  @override
  State<HealthRecordScreen> createState() => _HealthRecordScreenState();
}

class _HealthRecordScreenState extends State<HealthRecordScreen> {
  late Future<LifeMateHealthDocumentPage> _documents;
  LifeMateHealthDocumentCategory? _selectedCategory;
  String? _openingDocumentId;

  @override
  void initState() {
    super.initState();
    _documents = _load();
  }

  Future<LifeMateHealthDocumentPage> _load({String? cursor}) =>
      context.read<LifeMateApiClient>().getHealthDocumentPage(
        personId: widget.personId,
        category: _selectedCategory,
        cursor: cursor,
      );

  void _refresh() => setState(() => _documents = _load());

  void _selectCategory(LifeMateHealthDocumentCategory? value) {
    if (_selectedCategory == value) return;
    setState(() {
      _selectedCategory = value;
      _documents = _load();
    });
  }

  Future<void> _loadMore(LifeMateHealthDocumentPage current) async {
    final cursor = current.nextCursor;
    if (cursor == null) return;
    setState(() {
      _documents = _load(cursor: cursor).then(
        (next) => LifeMateHealthDocumentPage(
          items: [...current.items, ...next.items],
          nextCursor: next.nextCursor,
        ),
      );
    });
  }

  Future<void> _openDocument(LifeMateHealthDocument document) async {
    if (_openingDocumentId != null) return;
    setState(() => _openingDocumentId = document.id);
    try {
      final download = await context
          .read<LifeMateApiClient>()
          .getHealthDocumentDownload(document.id);
      final launched = await launchUrl(
        download.signedUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) _showOpenFailure();
    } catch (_) {
      if (mounted) _showOpenFailure();
    } finally {
      if (mounted) setState(() => _openingDocumentId = null);
    }
  }

  void _showOpenFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          LifeMateRuntimeLocale.select(
            fa: 'باز کردن فایل انجام نشد. دوباره تلاش کنید.',
            en: 'The document could not be opened. Try again.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<LifeMateHealthDocumentPage>(
          future: _documents,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final page = snapshot.data;
            final documents = page?.items ?? const <LifeMateHealthDocument>[];
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => _refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _RecordHeader(onBack: () => Navigator.of(context).maybePop()),
                  const SizedBox(height: 18),
                  _RecordHero(documentCount: documents.length),
                  const SizedBox(height: 20),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'مرور مدارک',
                      en: 'Browse documents',
                    ),
                    style: const TextStyle(
                      color: AppColors.darkBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _CategoryFilter(
                    selected: _selectedCategory,
                    onSelected: _selectCategory,
                  ),
                  const SizedBox(height: 16),
                  if (loading)
                    const _DocumentLoadingState()
                  else if (snapshot.hasError)
                    _DocumentErrorState(onRetry: _refresh)
                  else if (documents.isEmpty)
                    _DocumentEmptyState(filtered: _selectedCategory != null)
                  else ...[
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: '${documents.length} مدرک · جدیدترین ابتدا',
                        en: '${documents.length} documents · newest first',
                      ),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final document in documents) ...[
                      _HealthDocumentTile(
                        document: document,
                        opening: _openingDocumentId == document.id,
                        onOpen: () => _openDocument(document),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (page?.hasMore ?? false)
                      OutlinedButton.icon(
                        key: const Key('health-record-load-more'),
                        onPressed: () => _loadMore(page!),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(LifeMateRuntimeLocale.select(
                          fa: 'نمایش مدارک بیشتر',
                          en: 'Show more documents',
                        )),
                      ),
                  ],
                  const SizedBox(height: 12),
                  const _PrivacyNote(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RecordHeader extends StatelessWidget {
  const _RecordHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('health-record-back'),
          tooltip: LifeMateRuntimeLocale.select(fa: 'بازگشت', en: 'Back'),
          onPressed: onBack,
          icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
          color: AppColors.darkBlue,
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'پرونده سلامت',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  color: AppColors.darkBlue,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'مدارک درمانی شما، یک‌جا و خصوصی',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowDark.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.lock_rounded, color: AppColors.primary),
        ),
      ],
    );
  }
}

class _RecordHero extends StatelessWidget {
  const _RecordHero({required this.documentCount});

  final int documentCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.98),
            AppColors.primaryLight,
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.folder_shared_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: documentCount == 0
                    ? 'هر نسخه و نتیجه‌ای که ضمیمه کنید، اینجا می‌ماند.'
                    : '$documentCount مدرک خصوصی در پرونده شماست.',
                en: documentCount == 0
                    ? 'Prescriptions and results you attach will live here.'
                    : '$documentCount private documents are in your record.',
              ),
              style: const TextStyle(
                color: Colors.white,
                height: 1.55,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.selected, required this.onSelected});

  final LifeMateHealthDocumentCategory? selected;
  final ValueChanged<LifeMateHealthDocumentCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    final categories = <LifeMateHealthDocumentCategory?>[
      null,
      LifeMateHealthDocumentCategory.prescription,
      LifeMateHealthDocumentCategory.labResult,
      LifeMateHealthDocumentCategory.imaging,
      LifeMateHealthDocumentCategory.visit,
      LifeMateHealthDocumentCategory.injection,
      LifeMateHealthDocumentCategory.discharge,
      LifeMateHealthDocumentCategory.vaccination,
      LifeMateHealthDocumentCategory.other,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final category in categories) ...[
            ChoiceChip(
              key: ValueKey<String>('health-record-filter-${category?.wireValue ?? 'all'}'),
              label: Text(_documentCategoryLabel(category)),
              selected: selected == category,
              onSelected: (_) => onSelected(category),
              selectedColor: AppColors.primary.withValues(alpha: 0.18),
              labelStyle: TextStyle(
                color: selected == category
                    ? AppColors.darkBlue
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
              side: BorderSide(
                color: selected == category
                    ? AppColors.primary.withValues(alpha: 0.36)
                    : Colors.transparent,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _HealthDocumentTile extends StatelessWidget {
  const _HealthDocumentTile({
    required this.document,
    required this.opening,
    required this.onOpen,
  });

  final LifeMateHealthDocument document;
  final bool opening;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _documentCategoryColor(document.category);
    return Semantics(
      button: true,
      label: _documentCategoryLabel(document.category),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          key: ValueKey<String>('health-record-document-${document.id}'),
          borderRadius: BorderRadius.circular(22),
          onTap: opening ? null : onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_documentIcon(document), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _documentCategoryLabel(document.category),
                        style: const TextStyle(
                          color: AppColors.darkBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${document.capturedOn == null ? formatAppDate(context, document.createdAtUtc.toLocal()) : formatAppDate(context, document.capturedOn!)} · ${_formatSize(document.byteSize)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _SourcePill(sourceProduct: document.sourceProduct),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                opening
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.download_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.sourceProduct});

  final String sourceProduct;

  @override
  Widget build(BuildContext context) {
    final isWellMate = sourceProduct == 'wellmate';
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isWellMate ? 'WellMate' : sourceProduct,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DocumentLoadingState extends StatelessWidget {
  const _DocumentLoadingState();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 44),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _DocumentErrorState extends StatelessWidget {
  const _DocumentErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _StateCard(
    icon: Icons.cloud_off_rounded,
    title: 'پرونده در دسترس نیست',
    subtitle: 'اتصال را بررسی کنید و دوباره تلاش کنید.',
    actionLabel: 'تلاش دوباره',
    onAction: onRetry,
  );
}

class _DocumentEmptyState extends StatelessWidget {
  const _DocumentEmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) => _StateCard(
    icon: filtered ? Icons.filter_alt_off_rounded : Icons.folder_open_rounded,
    title: filtered ? 'مدرکی در این دسته نیست' : 'پرونده شما هنوز خالی است',
    subtitle: filtered
        ? 'دسته دیگری را انتخاب کنید.'
        : 'نسخه، آزمایش و تصویرهای پزشکی را هنگام ثبت درمان یا ویزیت ضمیمه کنید.',
  );
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 34),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 20),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'مدارک شما خصوصی‌اند. فایل فقط وقتی باز می‌شود که خودتان آن را انتخاب کنید.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _documentCategoryLabel(LifeMateHealthDocumentCategory? category) =>
    switch (category) {
      null => 'همه',
      LifeMateHealthDocumentCategory.prescription => 'نسخه',
      LifeMateHealthDocumentCategory.labResult => 'آزمایش',
      LifeMateHealthDocumentCategory.imaging => 'تصویربرداری',
      LifeMateHealthDocumentCategory.visit => 'ویزیت',
      LifeMateHealthDocumentCategory.injection => 'تزریق',
      LifeMateHealthDocumentCategory.discharge => 'ترخیص',
      LifeMateHealthDocumentCategory.vaccination => 'واکسن',
      LifeMateHealthDocumentCategory.other => 'سایر',
    };

IconData _documentIcon(LifeMateHealthDocument document) =>
    switch (document.category) {
      LifeMateHealthDocumentCategory.prescription => Icons.receipt_long_rounded,
      LifeMateHealthDocumentCategory.labResult => Icons.science_rounded,
      LifeMateHealthDocumentCategory.imaging => Icons.image_search_rounded,
      LifeMateHealthDocumentCategory.visit => Icons.medical_services_rounded,
      LifeMateHealthDocumentCategory.injection => Icons.vaccines_rounded,
      LifeMateHealthDocumentCategory.discharge => Icons.fact_check_rounded,
      LifeMateHealthDocumentCategory.vaccination => Icons.shield_rounded,
      LifeMateHealthDocumentCategory.other => document.contentType == 'application/pdf'
          ? Icons.picture_as_pdf_rounded
          : Icons.insert_drive_file_rounded,
    };

Color _documentCategoryColor(LifeMateHealthDocumentCategory category) =>
    switch (category) {
      LifeMateHealthDocumentCategory.prescription => AppColors.primary,
      LifeMateHealthDocumentCategory.labResult => Colors.blueAccent,
      LifeMateHealthDocumentCategory.imaging => Colors.deepPurple,
      LifeMateHealthDocumentCategory.visit => Colors.indigo,
      LifeMateHealthDocumentCategory.injection => Colors.orange,
      LifeMateHealthDocumentCategory.discharge => Colors.teal,
      LifeMateHealthDocumentCategory.vaccination => Colors.green,
      LifeMateHealthDocumentCategory.other => AppColors.textSecondary,
    };

String _formatSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
