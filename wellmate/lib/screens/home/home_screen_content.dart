import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/screens/home/active_treatment_card.dart';

import '../../core/theme/app_style.dart';
import '../../localization/app_localizations.dart';
import '../../models/schedule_item_model.dart';
import 'soft_schedule_card.dart';

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({
    super.key,
    required this.onOpenTreatments,
    required this.onAddTreatment,
  });

  final VoidCallback onOpenTreatments;
  final VoidCallback onAddTreatment;

  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  List<ScheduleItemModel> scheduleList = [];
  ScheduleItemModel? _nextOccurrence;
  Timer? _timer;
  bool isLoading = true;
  String? loadError;
  String _displayName = '';
  bool _hasTreatmentPlans = false;
  final Set<String> _submitting = {};

  @override
  void initState() {
    super.initState();
    _fetchScheduleFromBackend();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchScheduleFromBackend() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        loadError = null;
      });
    }
    try {
      final api = context.read<LifeMateApiClient>();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastVisibleDay = today.add(const Duration(days: 7));
      final results = await Future.wait([
        api.getCurrentUser(),
        api.getTreatmentPlans(),
        api.getDoseOccurrences(fromDate: today, toDate: lastVisibleDay),
      ]);
      final currentUser = results[0] as Map<String, dynamic>;
      final plans = results[1] as List<Map<String, dynamic>>;
      final doses = results[2] as List<Map<String, dynamic>>;
      final profile =
          currentUser['profile'] as Map<String, dynamic>? ?? const {};
      final plansById = <String, Map<String, dynamic>>{
        for (final plan in plans) plan['id'].toString(): plan,
      };

      final allItems = doses.map((dose) {
        final plan = plansById[dose['treatmentPlanId'].toString()] ?? const {};
        final medication = plan['medication'] is Map<String, dynamic>
            ? plan['medication'] as Map<String, dynamic>
            : const <String, dynamic>{};
        final status = (dose['status'] ?? 'scheduled').toString();
        final rawTime = (dose['scheduledLocalTime'] ?? '').toString();
        final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
        return ScheduleItemModel(
          id: dose['id'].toString(),
          type: 'medicine',
          title: (medication['name'] ?? 'دارو').toString(),
          time: time,
          dosage: (plan['doseText'] ?? '').toString(),
          status: status,
          version: dose['version'] is int ? dose['version'] as int : 1,
          scheduledAtUtc: DateTime.tryParse(
            dose['scheduledAtUtc']?.toString() ?? '',
          )?.toUtc(),
          isDone: status == 'taken' || status == 'skipped',
          frequency: 'طبق برنامه درمان',
          startDate: dose['scheduledLocalDate'] == null
              ? today
              : DateTime.tryParse(dose['scheduledLocalDate'].toString()),
          intervalDays: 1,
        );
      }).toList()
        ..sort(_compareOccurrence);

      final todayItems = allItems.where((item) {
        final date = item.startDate;
        return date != null && _sameDay(date, today);
      }).toList(growable: false);
      final actionable = allItems
          .where((item) => item.status == 'scheduled' || item.status == 'missed')
          .toList(growable: false);
      final future = actionable.where((item) {
        final scheduled = item.scheduledAtUtc;
        return scheduled == null || scheduled.isAfter(DateTime.now().toUtc());
      }).toList(growable: false);
      final nextOccurrence = future.isNotEmpty
          ? future.first
          : actionable.where((item) => item.status == 'missed').firstOrNull;

      if (!mounted) return;
      setState(() {
        _displayName = profile['displayName']?.toString().trim() ?? '';
        scheduleList = todayItems;
        _nextOccurrence = nextOccurrence;
        _hasTreatmentPlans = plans.isNotEmpty;
        isLoading = false;
      });
      context.read<MedicationProvider>().setMedications(todayItems);
      final timeZone = profile['timeZone']?.toString() ?? 'Asia/Tehran';
      try {
        await context.read<NotificationProvider>().syncDoseReminders(
              todayItems,
              timeZone: timeZone,
            );
      } catch (error) {
        debugPrint('WellMate reminder sync failed: $error');
      }
    } catch (error) {
      debugPrint('WellMate dose sync failed: $error');
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError = 'برنامه امروز دریافت نشد. اتصال را بررسی کنید.';
      });
    }
  }

  Future<void> _reportStatus(ScheduleItemModel item, String status) async {
    if (_submitting.contains(item.id)) return;
    setState(() => _submitting.add(item.id));

    try {
      final api = context.read<LifeMateApiClient>();
      final result = await api.reportDose(
        occurrenceId: item.id,
        clientRequestId: LifeMateApiClient.createClientRequestId(),
        version: item.version,
        status: status,
        occurredAtUtc: DateTime.now().toUtc(),
      );
      final updated = item.copyWith(
        isDone: status == 'taken' || status == 'skipped',
        status: (result['status'] ?? status).toString(),
        version: result['version'] is int
            ? result['version'] as int
            : item.version + 1,
      );
      if (!mounted) return;
      setState(() {
        final index =
            scheduleList.indexWhere((element) => element.id == item.id);
        if (index != -1) scheduleList[index] = updated;
        if (_nextOccurrence?.id == item.id) _nextOccurrence = null;
      });
      context.read<MedicationProvider>().setMedications(scheduleList);
      try {
        final current = await api.getCurrentUser();
        final profile =
            current['profile'] as Map<String, dynamic>? ?? const {};
        await context.read<NotificationProvider>().syncDoseReminders(
              scheduleList,
              timeZone: profile['timeZone']?.toString() ?? 'Asia/Tehran',
            );
      } catch (error) {
        debugPrint('WellMate reminder update failed: $error');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'taken'
                ? '${item.title} به عنوان مصرف‌شده ثبت شد.'
                : '${item.title} به عنوان مصرف‌نشده ثبت شد.',
            style: AppTextStyles.body(context).copyWith(color: Colors.white),
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchScheduleFromBackend();
    } catch (error) {
      debugPrint('WellMate dose report failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('ثبت مصرف انجام نشد؛ دوباره تلاش کنید.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting.remove(item.id));
    }
  }

  int _calculateSecondsLeft(ScheduleItemModel item) {
    final scheduledUtc = item.scheduledAtUtc;
    if (scheduledUtc != null) {
      final seconds = scheduledUtc.difference(DateTime.now().toUtc()).inSeconds;
      return seconds > 0 ? seconds : 0;
    }
    final parts = item.time.split(':');
    if (parts.length < 2) return 0;
    final now = DateTime.now();
    final date = item.startDate ?? now;
    final scheduleTime = DateTime(
      date.year,
      date.month,
      date.day,
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 0,
    );
    final seconds = scheduleTime.difference(now).inSeconds;
    return seconds > 0 ? seconds : 0;
  }

  String _getAssetPath(String type) {
    switch (type) {
      case 'visit':
        return 'assets/icons/stethoscope.png';
      case 'drop':
        return 'assets/icons/water_drop.png';
      default:
        return 'assets/icons/pill.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final font = AppTextStyles.body(context);
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';

    final unconsumedItems = scheduleList
        .where((item) => item.status == 'scheduled' || item.status == 'missed')
        .toList();
    final upcomingItems = unconsumedItems
        .where((item) => item.status == 'scheduled')
        .toList()
      ..sort(_compareOccurrence);
    final missedItems = unconsumedItems
        .where((item) => item.status == 'missed')
        .toList()
      ..sort(_compareOccurrence);
    final displayList = [...upcomingItems, ...missedItems];
    final nextItem = _nextOccurrence;

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 16),
              child: Text(
                isPersian
                    ? (_displayName.isEmpty
                        ? 'سلام،'
                        : 'سلام $_displayName جان،')
                    : (_displayName.isEmpty ? 'Hello,' : 'Hi $_displayName,'),
                style: font.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          if (isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (loadError != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 52,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(loadError!, textAlign: TextAlign.center, style: font),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _fetchScheduleFromBackend,
                        child: const Text('تلاش دوباره'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: nextItem == null
                  ? _TreatmentTimerPlaceholder(
                      hasTreatmentPlans: _hasTreatmentPlans,
                      onAction: _hasTreatmentPlans
                          ? widget.onOpenTreatments
                          : widget.onAddTreatment,
                      font: font,
                    )
                  : ActiveTreatmentCard(
                      treatmentName: nextItem.title,
                      dose: nextItem.dosage,
                      time: nextItem.time,
                      assetIconPath: _getAssetPath(nextItem.type),
                      progressValue: 1.0 -
                          (_calculateSecondsLeft(nextItem) / 86400)
                              .clamp(0.0, 1.0),
                      secondsLeft: _calculateSecondsLeft(nextItem),
                      onTaken: _submitting.contains(nextItem.id)
                          ? null
                          : () => _reportStatus(nextItem, 'taken'),
                      onSkipped: _submitting.contains(nextItem.id)
                          ? null
                          : () => _reportStatus(nextItem, 'skipped'),
                      onEdit: widget.onOpenTreatments,
                      isSubmitting: _submitting.contains(nextItem.id),
                      font: font,
                    ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 24,
                        end: 24,
                        top: 24,
                        bottom: 16,
                      ),
                      child: Text(
                        loc['today_schedule'] ?? 'برنامه امروز',
                        style: font.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: displayList.isEmpty
                          ? _HomeEmptyState(
                              hasTreatmentPlans: _hasTreatmentPlans,
                              hadDosesToday: scheduleList.isNotEmpty,
                              onAddTreatment: widget.onAddTreatment,
                              font: font,
                            )
                          : ListView.separated(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                24,
                                0,
                                24,
                                100,
                              ),
                              itemCount: displayList.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final item = displayList[i];
                                final isMissed = missedItems.contains(item);
                                return SoftScheduleCard(
                                  item: item,
                                  index: i,
                                  font: font,
                                  assetPath: _getAssetPath(item.type),
                                  isMissed: isMissed,
                                  onTaken: isMissed &&
                                          !_submitting.contains(item.id)
                                      ? () => _reportStatus(item, 'taken')
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static int _compareOccurrence(
    ScheduleItemModel a,
    ScheduleItemModel b,
  ) {
    final aDate = a.scheduledAtUtc;
    final bDate = b.scheduledAtUtc;
    if (aDate != null && bDate != null) return aDate.compareTo(bDate);
    final dateCompare = (a.startDate ?? DateTime(1970))
        .compareTo(b.startDate ?? DateTime(1970));
    return dateCompare != 0 ? dateCompare : a.time.compareTo(b.time);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _TreatmentTimerPlaceholder extends StatelessWidget {
  const _TreatmentTimerPlaceholder({
    required this.hasTreatmentPlans,
    required this.onAction,
    required this.font,
  });

  final bool hasTreatmentPlans;
  final VoidCallback onAction;
  final TextStyle font;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowDark.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasTreatmentPlans
                            ? 'دوز بعدی هنوز ساخته نشده است'
                            : 'تایمر درمان آماده است',
                        style: font.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasTreatmentPlans
                            ? 'برنامه درمان فعال است؛ برای دیدن جزئیات و روزهای مصرف وارد درمان‌ها شوید.'
                            : 'پس از ثبت اولین دارو، شمارش معکوس دوز بعدی در همین کارت نمایش داده می‌شود.',
                        style: font.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: 0,
                        strokeWidth: 8,
                        backgroundColor: AppColors.background,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primaryLight,
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/icons/pill.png',
                            width: 34,
                            height: 34,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.medication_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '--:--',
                            textDirection: TextDirection.ltr,
                            style: font.copyWith(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAction,
                icon: Icon(
                  hasTreatmentPlans
                      ? Icons.list_alt_rounded
                      : Icons.add_rounded,
                ),
                label: Text(
                  hasTreatmentPlans ? 'مشاهده درمان‌ها' : 'افزودن درمان',
                ),
              ),
            ),
          ],
        ),
      );
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({
    required this.hasTreatmentPlans,
    required this.hadDosesToday,
    required this.onAddTreatment,
    required this.font,
  });

  final bool hasTreatmentPlans;
  final bool hadDosesToday;
  final VoidCallback onAddTreatment;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    final title = !hasTreatmentPlans
        ? 'هنوز برنامه درمانی ثبت نشده است.'
        : hadDosesToday
            ? 'همه داروهای امروز ثبت شده‌اند!'
            : 'برای امروز دوزی برنامه‌ریزی نشده است.';
    final subtitle = !hasTreatmentPlans
        ? 'اولین دارو و زمان مصرف را اضافه کنید تا برنامه روزانه ساخته شود.'
        : hadDosesToday
            ? 'برای مشاهده جزئیات روزهای دیگر به تقویم بروید.'
            : 'برنامه درمان فعال است، اما برای امروز دوزی از Backend برنگشته است.';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                !hasTreatmentPlans
                    ? Icons.medication_liquid_rounded
                    : Icons.check_circle_outline_rounded,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: font.copyWith(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: font.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            if (!hasTreatmentPlans) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAddTreatment,
                icon: const Icon(Icons.add_rounded),
                label: const Text('افزودن درمان'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
