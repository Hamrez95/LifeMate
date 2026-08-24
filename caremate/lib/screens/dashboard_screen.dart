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
      final kind = switch (item.type) {
        CareItemType.injection => 'injection',
        CareItemType.visit => 'appointment',
        CareItemType.medication => 'medication',
      };
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
      final kind = switch (item.type) {
        CareItemType.injection => 'injection',
        CareItemType.visit => 'appointment',
        CareItemType.medication => 'medication',
      };
      alerts.add(
        CareRecipientAlert(
          patientUserId: item.patientUserId,
          patientName: item.patientDisplayName,
          occurrenceId: item.occurrenceId,
          title: item.title,
          subtitle: item.subtitle,
          scheduledAtUtc: item.scheduledAt.toUtc(),
          kind: kind,
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
      builder: (sheetContext) => Container(
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
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.55,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: alerts.length,
                  itemBuilder: (_, index) {
                    final item = alerts[index];
                    CareHomeRelationship? relationship;
                    for (final candidate in snapshot.relationships) {
                      if (candidate.patientUserId == item.patientUserId) {
                        relationship = candidate;
                        break;
                      }
                    }
                    final canCall = relationship?.patientPhoneNumber != null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CareHomeTreatmentListTile(
                          item: item,
                          isPersian: isPersian,
                          compact: true,
                        ),
                        if (canCall)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Semantics(
                              button: true,
                              label: LifeMateRuntimeLocale.select(
                                fa: 'تماس با ${item.patientDisplayName}',
                                en: 'Call ${item.patientDisplayName}',
                              ),
                              child: TextButton.icon(
                                onPressed: () async {
                                  final opened = await context
                                      .read<CareNotificationProvider>()
                                      .openPatientDialer(item.patientUserId);
                                  if (!opened && mounted) {
                                    LifeMateNotice.show(
                                      context,
                                      message: LifeMateRuntimeLocale.select(
                                        fa: 'شماره تماس معتبر دیگر در دسترس نیست.',
                                        en: 'A valid phone number is no longer available.',
                                      ),
                                      type: LifeMateNoticeType.info,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.call_outlined, size: 18),
                                label: Text(
                                  LifeMateRuntimeLocale.select(
                                    fa: 'تماس',
                                    en: 'Call',
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
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
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'اتصال به WellMate',
                    en: "Connect to WellMate",
                  ),
                  en: "Connect to WellMate",
                ),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ساده‌ترین روش، اسکن QR روی گوشی فرد تحت مراقبت است.',
                    en: "The easiest way is to scan the QR on the phone of the person under care.",
                  ),
                  en: "The easiest way is to scan the QR on the phone of the person under care.",
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondaryText),
              ),
              SizedBox(height: 18),
              ListTile(
                leading: CircleAvatar(
                  child: Icon(Icons.qr_code_scanner_rounded),
                ),
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'اسکن QR',
                      en: "QR scan",
                    ),
                    en: "QR scan",
                  ),
                ),
                subtitle: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'اتصال کوتاه‌مدت و یک‌بارمصرف',
                      en: "Short-term and disposable connection",
                    ),
                    en: "Short-term and disposable connection",
                  ),
                ),
                onTap: () => Navigator.pop(context, 'qr'),
              ),
              ListTile(
                leading: CircleAvatar(child: Icon(Icons.keyboard_rounded)),
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ورود کد دعوت',
                      en: "Enter the invitation code",
                    ),
                    en: "Enter the invitation code",
                  ),
                ),
                subtitle: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'روش پشتیبان برای کد کپی‌شده',
                      en: "Backup method for copied code",
                    ),
                    en: "Backup method for copied code",
                  ),
                ),
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
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پذیرش مراقبت؟',
              en: "Acceptance of care?",
            ),
            en: "Acceptance of care?",
          ),
        ),
        content: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'با تأیید، اطلاعات فقط در محدوده رضایت صاحب حساب در CareMate نمایش داده می‌شود.',
              en: "Upon approval, information will only be displayed on CareMate to the extent of the account holder's consent.",
            ),
            en: "Upon approval, information will only be displayed on CareMate to the extent of the account holder's consent.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
                en: "opt out",
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تأیید و اتصال',
                  en: "Confirm and connect",
                ),
                en: "Confirm and connect",
              ),
            ),
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
          title: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'پذیرش دعوت مراقبت',
                en: "Accept the invitation to care",
              ),
              en: "Accept the invitation to care",
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'کدی را وارد کنید که صاحب WellMate مستقیماً برای شما ارسال کرده است.',
                    en: "Enter the code sent directly to you by the owner of WellMate.",
                  ),
                  en: "Enter the code sent directly to you by the owner of WellMate.",
                ),
                style: TextStyle(height: 1.55),
              ),
              SizedBox(height: 14),
              TextField(
                controller: controller,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'کد دعوت',
                      en: "invitation code",
                    ),
                    en: "invitation code",
                  ),
                  prefixIcon: Icon(Icons.vpn_key_rounded),
                  filled: true,
                  fillColor: Color(0xFFF6F9FD),
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
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'محدوده دسترسی مراقبتی و حریم خصوصی فرد را می‌پذیرم.',
                      en: "I accept the scope of care access and individual privacy.",
                    ),
                    en: "I accept the scope of care access and individual privacy.",
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
                  en: "opt out",
                ),
              ),
            ),
            FilledButton(
              onPressed: consent && controller.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, controller.text.trim())
                  : null,
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'پذیرش امن',
                    en: "Safe reception",
                  ),
                  en: "Safe reception",
                ),
              ),
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
      await context.read<LifeMateApiClient>().acceptCareInvitation(
        token: token,
      );
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ارتباط مراقبتی با موفقیت فعال شد.',
            en: "Care connection successfully activated.",
          ),
          en: "Care connection successfully activated.",
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
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  void _onNavigationTap(int index) {
    final shellNavigation = widget.onNavigationTap;
    if (shellNavigation != null) {
      shellNavigation(index);
      return;
    }
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
                      _InlineRetry(
                        message: _error!,
                        onRetry: _refresh,
                        font: font,
                      ),
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
        routeTreatmentScreen: widget.onNavigationTap == null,
        onTreatmentManagementReturned: () => unawaited(_refresh()),
      ),
    );
  }

  static String _friendlyApiError(LifeMateApiException error) {
    switch (error.code) {
      case 'care_access_denied':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'یکی از دسترسی‌های مراقبتی تغییر کرده است. صفحه را تازه‌سازی کنید.',
            en: "One of the care accesses has changed. Refresh the page.",
          ),
          en: "One of the care accesses has changed. Refresh the page.",
        );
      case 'invitation_contact_mismatch':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'این دعوت برای حساب دیگری صادر شده است.',
            en: "This invitation has been issued for another account.",
          ),
          en: "This invitation has been issued for another account.",
        );
      case 'invitation_expired':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'مهلت این دعوت تمام شده است؛ دعوت جدید بخواهید.',
            en: "The deadline for this invitation has expired; Ask for a new invitation.",
          ),
          en: "The deadline for this invitation has expired; Ask for a new invitation.",
        );
      case 'invitation_not_found':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'کد دعوت معتبر نیست.',
            en: "The invitation code is not valid.",
          ),
          en: "The invitation code is not valid.",
        );
      default:
        return error.isUnauthorized
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
                  en: "Your session has expired. Sign in again.",
                ),
                en: "Your session has expired. Sign in again.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'درخواست انجام نشد. دوباره تلاش کنید.',
                  en: "Request failed. Try again.",
                ),
                en: "Request failed. Try again",
              );
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
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'در حال آماده‌سازی صف مراقبت…',
                  en: "Preparing care queue…",
                ),
                en: "Preparing care queue…",
              ),
              style: font.copyWith(
                fontSize: 12,
                color: AppColors.secondaryText,
              ),
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
            style: font.copyWith(fontSize: 11.5, color: Color(0xFFB14955)),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تلاش دوباره',
                en: "Try again",
              ),
              en: "Try again",
            ),
          ),
        ),
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
      padding: EdgeInsets.all(20),
      decoration: AppColors.softDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.family_restroom_rounded,
            color: AppColors.primaryBlue,
            size: 42,
          ),
          SizedBox(height: 10),
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هنوز فردی به مراقبت شما متصل نیست',
                en: "No one is connected to your care yet",
              ),
              en: "No one is connected to your care yet",
            ),
            textAlign: TextAlign.center,
            style: font.copyWith(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 7),
          Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'با دعوت WellMate ارتباط مراقبتی امن را فعال کنید.',
                en: "Enable secure care communication by inviting WellMate.",
              ),
              en: "Enable secure care communication by inviting WellMate.",
            ),
            textAlign: TextAlign.center,
            style: font.copyWith(fontSize: 11.5, color: Color(0xFF7D8B9D)),
          ),
          SizedBox(height: 14),
          FilledButton.icon(
            onPressed: accepting ? null : onTap,
            icon: accepting
                ? SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.person_add_alt_1_rounded),
            label: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'افزودن فرد تحت مراقبت',
                  en: "Add a person under care",
                ),
                en: "Add a person under care",
              ),
            ),
          ),
        ],
      ),
    );
  }
}
