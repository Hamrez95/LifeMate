import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/localization/locale_provider.dart';
import '../models/care_home_snapshot.dart';
import '../models/care_recipient_alert.dart';
import '../models/care_recipient_reminder.dart';
import '../providers/care_notification_provider.dart';
import '../services/care_home_aggregator.dart';
import '../widgets/care_home_cards.dart';
import '../widgets/caremate_bottom_nav.dart';
import '../widgets/custom_app_header.dart';
import 'calendar/calendar_screen.dart';
import 'feature_preview_screen.dart';
import 'pairing/care_invitation_scanner_screen.dart';
import 'women_calendar/care_women_calendar_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.refreshToken = 0,
    this.onNavigationTap,
  });

  final int refreshToken;
  final ValueChanged<int>? onNavigationTap;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  CareHomeSnapshot? _snapshot;
  bool _loading = true;
  bool _accepting = false;
  String? _error;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await CareHomeAggregator(
        context.read<LifeMateApiClient>(),
      ).load();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      await _syncCareRecipientNotifications(snapshot);
    } on LifeMateApiException catch (error) {
      _setLoadError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate home refresh failed: $error');
      _setLoadError(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات مراقبت دریافت نشد. اتصال اینترنت را بررسی کنید.',
            en: "Care information not received. Check your internet connection.",
          ),
          en: "Care information not received. Check your internet connection.",
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setLoadError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    LifeMateNotice.show(
      context,
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'دریافت اطلاعات انجام نشد',
          en: "Information could not be received",
        ),
        en: "Information could not be received",
      ),
      message: message,
      type: LifeMateNoticeType.error,
    );
  }

  Future<void> _syncCareRecipientNotifications(
    CareHomeSnapshot snapshot,
  ) async {
    final now = DateTime.now().toUtc();
    final horizon = now.add(const Duration(days: 7));
    final reminders = <CareRecipientReminder>[];
    final alerts = <CareRecipientAlert>[];

    for (final item in snapshot.queueItems) {
      final scheduledUtc = item.scheduledAt.toUtc();
      if (!scheduledUtc.isAfter(now) || scheduledUtc.isAfter(horizon)) continue;
      final kind = _notificationKind(item.type);
      reminders.add(
        CareRecipientReminder(
          patientUserId: item.patientUserId,
          patientName: item.patientDisplayName,
          doseId: item.occurrenceId,
          medicationName: item.title,
          doseText: item.subtitle,
          scheduledAtUtc: scheduledUtc,
          reminderMinutesBefore: LifeMateReminderLeadTimes.normalize(
            item.raw['caregiverReminderMinutesBefore'],
            fallback: LifeMateReminderLeadTimes.defaultCaregiverMinutes,
          ),
          kind: kind,
        ),
      );
    }

    for (final item in snapshot.todayItems.where((item) => item.isAlert)) {
      alerts.add(
        CareRecipientAlert(
          patientUserId: item.patientUserId,
          patientName: item.patientDisplayName,
          occurrenceId: item.occurrenceId,
          title: item.title,
          subtitle: item.subtitle,
          scheduledAtUtc: item.scheduledAt.toUtc(),
          kind: _notificationKind(item.type),
          status: item.status,
        ),
      );
    }

    if (!mounted) return;
    final profile = snapshot.currentUser['profile'] is Map<String, dynamic>
        ? snapshot.currentUser['profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final isPersian =
        context.read<LocaleProvider>().locale.languageCode == 'fa';
    try {
      final notificationProvider = context.read<CareNotificationProvider>();
      await notificationProvider.syncEarliestPerRecipient(
        reminders,
        timeZone: profile['timeZone']?.toString() ?? 'Asia/Tehran',
        isPersian: isPersian,
      );
      await notificationProvider.syncMissedAlerts(
        alerts,
        isPersian: isPersian,
      );
    } catch (error) {
      debugPrint('CareMate home notification sync failed: $error');
    }
  }

  static String _notificationKind(CareItemType type) => switch (type) {
    CareItemType.injection => 'injection',
    CareItemType.visit => 'appointment',
    CareItemType.medication => 'medication',
  };

  void _showAlerts() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final alerts = snapshot.todayItems
        .where((item) => item.isAlert)
        .toList(growable: false);
    if (alerts.isEmpty) {
      LifeMateNotice.show(
        context,
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'در حال حاضر هشدار درمانی فعالی وجود ندارد.',
            en: "There is currently no active treatment alert.",
          ),
          en: "There is currently no active treatment alert.",
        ),
        type: LifeMateNoticeType.info,
      );
      return;
    }
    final isPersian =
        context.read<LocaleProvider>().locale.languageCode == 'fa';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'هشدارهای درمانی امروز',
                    en: "Today's medical warnings",
                  ),
                  en: "Today's medical warnings",
                ),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: alerts.length,
                  itemBuilder: (_, index) => CareHomeTreatmentListTile(
                    item: alerts[index],
                    isPersian: isPersian,
                    compact: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCompanion() {
    final companion = _snapshot?.companion;
    final relationship = companion?.relationship;
    if (companion == null || !companion.hasPermission || relationship == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CareWomenCalendarScreen(
          patientUserId: relationship.patientUserId,
          patientName: relationship.patientDisplayName,
        ),
      ),
    );
  }

  Future<void> _showPairingOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(24, 18, 24, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3E7EA),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded),
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'اسکن دعوت مراقبت',
                      en: 'Scan care invitation',
                    ),
                    en: 'Scan care invitation',
                  ),
                ),
                onTap: () => Navigator.pop(context, 'scan'),
              ),
              ListTile(
                leading: const Icon(Icons.keyboard_alt_outlined),
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ورود کد دعوت',
                      en: 'Enter invitation code',
                    ),
                    en: 'Enter invitation code',
                  ),
                ),
                onTap: () => Navigator.pop(context, 'code'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'scan') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const CareInvitationScannerScreen(),
        ),
      );
      if (mounted) unawaited(_refresh());
      return;
    }
    await _showInvitationCodeDialog();
  }

  Future<void> _showInvitationCodeDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'کد دعوت را وارد کنید',
              en: 'Enter invitation code',
            ),
            en: 'Enter invitation code',
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: 'Cancel'),
                en: 'Cancel',
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'ادامه', en: 'Continue'),
                en: 'Continue',
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || code == null || code.isEmpty) return;
    await _acceptInvitation(code);
  }

  Future<void> _acceptInvitation(String code) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    try {
      await context.read<LifeMateApiClient>().acceptCareInvitation(code);
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'دعوت مراقبت با موفقیت پذیرفته شد.',
            en: 'Care invitation accepted successfully.',
          ),
          en: 'Care invitation accepted successfully.',
        ),
        type: LifeMateNoticeType.success,
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        message: _friendlyApiError(error),
        type: LifeMateNoticeType.error,
      );
    } catch (error) {
      debugPrint('CareMate invitation accept failed: $error');
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'پذیرش دعوت انجام نشد. دوباره تلاش کنید.',
            en: 'Invitation could not be accepted. Try again.',
          ),
          en: 'Invitation could not be accepted. Try again.',
        ),
        type: LifeMateNoticeType.error,
      );
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final isPersian =
        context.watch<LocaleProvider>().locale.languageCode == 'fa';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 112),
            children: [
              CustomAppHeader(
                notificationCount: snapshot?.alertsToday ?? 0,
                onNotificationTap: _showAlerts,
              ),
              const SizedBox(height: 18),
              if (_loading && snapshot == null)
                const _CareHomeLoadingState()
              else if (_error != null && snapshot == null)
                _CareHomeErrorState(message: _error!, onRetry: _refresh)
              else if (snapshot != null) ...[
                CareHomeHeroCard(snapshot: snapshot, isPersian: isPersian),
                const SizedBox(height: 14),
                CareHomeProgressCard(snapshot: snapshot, isPersian: isPersian),
                const SizedBox(height: 14),
                CareHomeCompanionCard(
                  summary: snapshot.companion,
                  isPersian: isPersian,
                  onTap: _openCompanion,
                ),
                const SizedBox(height: 14),
                CareHomeTodayCard(snapshot: snapshot, isPersian: isPersian),
                const SizedBox(height: 14),
                CareHomePairingCard(onTap: _showPairingOptions),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.onNavigationTap == null
          ? const CareMateBottomNav(currentIndex: 0)
          : null,
    );
  }
}

String _friendlyApiError(LifeMateApiException error) => switch (error.code) {
  'offline' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(
      fa: 'به اینترنت متصل نیستید. اتصال را بررسی کنید و دوباره تلاش کنید.',
      en: 'You are offline. Check your connection and try again.',
    ),
    en: 'You are offline. Check your connection and try again.',
  ),
  'timeout' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(
      fa: 'پاسخ سرویس طول کشید. دوباره تلاش کنید.',
      en: 'The service took too long to respond. Try again.',
    ),
    en: 'The service took too long to respond. Try again.',
  ),
  'care_invitation_invalid',
  'care_invitation_expired',
  'care_invitation_used',
  'care_invitation_revoked' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(
      fa: 'این دعوت معتبر یا قابل استفاده نیست.',
      en: 'This invitation is not valid or usable.',
    ),
    en: 'This invitation is not valid or usable.',
  ),
  'care_invitation_self' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(
      fa: 'نمی‌توانید دعوت مراقبت متعلق به خودتان را بپذیرید.',
      en: 'You cannot accept your own care invitation.',
    ),
    en: 'You cannot accept your own care invitation.',
  ),
  'unauthorized' => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(
      fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
      en: 'Your session has expired. Sign in again.',
    ),
    en: 'Your session has expired. Sign in again.',
  ),
  _ => LifeMateRuntimeLocale.select(
    fa: LifeMateRuntimeLocale.select(
      fa: 'درخواست انجام نشد. دوباره تلاش کنید.',
      en: 'The request could not be completed. Try again.',
    ),
    en: 'The request could not be completed. Try again.',
  ),
};

class _CareHomeLoadingState extends StatelessWidget {
  const _CareHomeLoadingState();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 72),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _CareHomeErrorState extends StatelessWidget {
  const _CareHomeErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_rounded, size: 42),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: onRetry,
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Retry'),
              en: 'Retry',
            ),
          ),
        ),
      ],
    ),
  );
}
