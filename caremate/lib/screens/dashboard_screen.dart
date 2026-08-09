import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/localization/locale_provider.dart';
import '../models/care_home_snapshot.dart';
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
  const DashboardScreen({super.key});

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
      _setLoadError('اطلاعات مراقبت دریافت نشد. اتصال اینترنت را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setLoadError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    LifeMateNotice.show(
      context,
      title: 'دریافت اطلاعات انجام نشد',
      message: message,
      type: LifeMateNoticeType.error,
    );
  }

  Future<void> _syncCareRecipientNotifications(
    CareHomeSnapshot snapshot,
  ) async {
    final now = DateTime.now().toUtc();
    final horizon = now.add(const Duration(days: 7));
    final candidates = <CareRecipientReminder>[];
    for (final item in snapshot.queueItems) {
      final scheduledUtc = item.scheduledAt.toUtc();
      if (!scheduledUtc.isAfter(now) || scheduledUtc.isAfter(horizon)) continue;
      final kind = switch (item.type) {
        CareItemType.injection => 'injection',
        CareItemType.visit => 'appointment',
        CareItemType.medication => 'medication',
      };
      candidates.add(
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
    if (!mounted) return;
    final profile = snapshot.currentUser['profile'] is Map<String, dynamic>
        ? snapshot.currentUser['profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final isPersian =
        context.read<LocaleProvider>().locale.languageCode == 'fa';
    try {
      await context.read<CareNotificationProvider>().syncEarliestPerRecipient(
        candidates,
        timeZone: profile['timeZone']?.toString() ?? 'Asia/Tehran',
        isPersian: isPersian,
      );
    } catch (error) {
      debugPrint('CareMate home notification sync failed: $error');
    }
  }

  void _showAlerts() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final alerts = snapshot.todayItems
        .where((item) => item.isAlert)
        .toList(growable: false);
    if (alerts.isEmpty) {
      LifeMateNotice.show(
        context,
        message: 'در حال حاضر هشدار درمانی فعالی وجود ندارد.',
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'هشدارهای درمانی امروز',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
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
    if (companion == null ||
        !companion.hasPermission ||
        relationship == null) {
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
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'اتصال به WellMate',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'ساده‌ترین روش، اسکن QR روی گوشی فرد تحت مراقبت است.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.qr_code_scanner_rounded),
                ),
                title: const Text('اسکن QR'),
                subtitle: const Text('اتصال کوتاه‌مدت و یک‌بارمصرف'),
                onTap: () => Navigator.pop(context, 'qr'),
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.keyboard_rounded)),
                title: const Text('ورود کد دعوت'),
                subtitle: const Text('روش پشتیبان برای کد کپی‌شده'),
                onTap: () => Navigator.pop(context, 'manual'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'qr') {
      await _showQrScanner();
    } else if (action == 'manual') {
      await _showAcceptInvitation();
    }
  }

  Future<void> _showQrScanner() async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const CareInvitationScannerScreen(),
      ),
    );
    if (token == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پذیرش مراقبت؟'),
        content: const Text(
          'با تأیید، اطلاعات فقط در محدوده رضایت صاحب حساب در CareMate نمایش داده می‌شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأیید و اتصال'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _acceptInvitationToken(token);
  }

  Future<void> _showAcceptInvitation() async {
    final controller = TextEditingController();
    var consent = false;
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('پذیرش دعوت مراقبت'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'کدی را وارد کنید که صاحب WellMate مستقیماً برای شما ارسال کرده است.',
                style: TextStyle(height: 1.55),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'کد دعوت',
                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF6F9FD),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) =>
                    setDialogState(() => consent = value ?? false),
                title: const Text(
                  'محدوده دسترسی مراقبتی و حریم خصوصی فرد را می‌پذیرم.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: consent && controller.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, controller.text.trim())
                  : null,
              child: const Text('پذیرش امن'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (token == null || !mounted) return;
    await _acceptInvitationToken(token);
  }

  Future<void> _acceptInvitationToken(String token) async {
    if (_accepting) return;
    setState(() => _accepting = true);
    try {
      await context.read<LifeMateApiClient>().acceptCareInvitation(token: token);
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        message: 'ارتباط مراقبتی با موفقیت فعال شد.',
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
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  void _onNavigationTap(int index) {
    if (index == 4) return;
    final Widget destination = index == 0
        ? const CalendarScreen()
        : CareMateFeaturePreviewScreen(initialIndex: index);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final font = TextStyle(
      fontFamily: isPersian ? 'Vazir' : 'Poppins',
      color: AppColors.primaryText,
    );
    final snapshot = _snapshot;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            key: const ValueKey('care-home-global-dashboard'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 18),
            children: [
              CustomAppHeader(
                onNotificationTap: _showAlerts,
                showNotificationDot: (snapshot?.alertsToday ?? 0) > 0,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Column(
                  children: [
                    if (snapshot == null && _loading)
                      _LoadingQueueShell(font: font)
                    else
                      CareHomeTreatmentQueueCard(
                        current: snapshot?.currentTreatment,
                        next: snapshot?.nextTreatment,
                        isPersian: isPersian,
                        font: font,
                      ),
                    if (_loading && snapshot != null) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _InlineRetry(message: _error!, onRetry: _refresh, font: font),
                    ],
                    if (snapshot != null && snapshot.relationships.isEmpty) ...[
                      const SizedBox(height: 18),
                      _ConnectCareCard(
                        accepting: _accepting,
                        onTap: _showPairingOptions,
                        font: font,
                      ),
                    ] else if (snapshot != null) ...[
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CareHomeCompanionCard(
                              summary: snapshot.companion,
                              isPersian: isPersian,
                              font: font,
                              onTap: snapshot.companion.hasPermission
                                  ? _openCompanion
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: CareHomeChildPreviewCard(font: font)),
                        ],
                      ),
                      const SizedBox(height: 18),
                      CareHomeWomenCalendarCard(
                        summary: snapshot.companion,
                        font: font,
                        onTap: snapshot.companion.hasPermission
                            ? _openCompanion
                            : null,
                      ),
                      const SizedBox(height: 18),
                      CareHomeSummaryCard(
                        snapshot: snapshot,
                        isPersian: isPersian,
                        font: font,
                      ),
                      const SizedBox(height: 18),
                      CareHomeTodayPlanCard(
                        items: snapshot.todayItems,
                        isPersian: isPersian,
                        font: font,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: 4,
        onTap: _onNavigationTap,
        onTreatmentManagementReturned: () => unawaited(_refresh()),
      ),
    );
  }

  static String _friendlyApiError(LifeMateApiException error) {
    switch (error.code) {
      case 'care_access_denied':
        return 'یکی از دسترسی‌های مراقبتی تغییر کرده است. صفحه را تازه‌سازی کنید.';
      case 'invitation_contact_mismatch':
        return 'این دعوت برای حساب دیگری صادر شده است.';
      case 'invitation_expired':
        return 'مهلت این دعوت تمام شده است؛ دعوت جدید بخواهید.';
      case 'invitation_not_found':
        return 'کد دعوت معتبر نیست.';
      default:
        return error.isUnauthorized
            ? 'نشست شما منقضی شده است. دوباره وارد شوید.'
            : 'درخواست انجام نشد. دوباره تلاش کنید.';
    }
  }
}

class _LoadingQueueShell extends StatelessWidget {
  const _LoadingQueueShell({required this.font});

  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 286,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'در حال آماده‌سازی صف مراقبت…',
              style: font.copyWith(fontSize: 12, color: AppColors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineRetry extends StatelessWidget {
  const _InlineRetry({
    required this.message,
    required this.onRetry,
    required this.font,
  });

  final String message;
  final Future<void> Function() onRetry;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: font.copyWith(fontSize: 11.5, color: const Color(0xFFB14955)),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
      ],
    );
  }
}

class _ConnectCareCard extends StatelessWidget {
  const _ConnectCareCard({
    required this.accepting,
    required this.onTap,
    required this.font,
  });

  final bool accepting;
  final VoidCallback onTap;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppColors.softDecoration(),
      child: Column(
        children: [
          const Icon(
            Icons.family_restroom_rounded,
            color: AppColors.primaryBlue,
            size: 42,
          ),
          const SizedBox(height: 10),
          Text(
            'هنوز فردی به مراقبت شما متصل نیست',
            textAlign: TextAlign.center,
            style: font.copyWith(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(
            'با دعوت WellMate ارتباط مراقبتی امن را فعال کنید.',
            textAlign: TextAlign.center,
            style: font.copyWith(fontSize: 11.5, color: const Color(0xFF7D8B9D)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: accepting ? null : onTap,
            icon: accepting
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('افزودن فرد تحت مراقبت'),
          ),
        ],
      ),
    );
  }
}
