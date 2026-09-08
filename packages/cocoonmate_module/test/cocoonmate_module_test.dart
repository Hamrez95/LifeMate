import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

class FakeHost implements CocoonHostContract {
  FakeHost(this.entryState, this.locale, {this.pregnancySnapshot});

  @override
  CocoonEntryState entryState;
  @override
  Locale locale;
  @override
  String? personId = 'synthetic-person';
  @override
  CocoonPregnancySnapshot? offlinePregnancySnapshot;
  @override
  CocoonPregnancySnapshot? pregnancySnapshot;

  @override
  Future<void> beginPregnancySetup() async {}
  @override
  Future<void> openCommerce() async {}
  @override
  Future<void> openGlobalProfile() async {}
  @override
  Future<void> openLogin() async {}
  @override
  Future<void> refresh() async {}
  @override
  void recordSafeEvent(String name) {}
}

Widget appFor(FakeHost host) => MaterialApp(
      theme: CocoonTheme.light(),
      home: CocoonMateModule(config: CocoonModuleConfig(host: host)),
    );

void main() {
  testWidgets('module mounts under a host and uses Persian RTL', (
    tester,
  ) async {
    final host = FakeHost(CocoonEntryState.activePregnancy, const Locale('fa'));
    await tester.pumpWidget(appFor(host));

    expect(find.text('خانه'), findsOneWidget);
    final directionality = tester.widget<Directionality>(
      find
          .descendant(
            of: find.byType(CocoonMateModule),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('English LTR entitlement gate is deterministic', (tester) async {
    final host = FakeHost(CocoonEntryState.notEntitled, const Locale('en'));
    await tester.pumpWidget(appFor(host));

    expect(find.text('Choose access to CocoonMate'), findsOneWidget);
    expect(find.text('View options'), findsOneWidget);
  });

  testWidgets('protected owner snapshot keeps shell available while offline', (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.offlineOwnerPregnancy,
      const Locale('en'),
    );
    await tester.pumpWidget(appFor(host));

    expect(find.text('Home'), findsOneWidget);
    expect(
      find.text('Last protected information saved on this device'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('large text does not require root navigator ownership', (
    tester,
  ) async {
    final host = FakeHost(CocoonEntryState.noPregnancy, const Locale('en'));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: appFor(host),
      ),
    );
    expect(find.text('No active pregnancy yet'), findsOneWidget);
  });

  testWidgets('home presents canonical gestational age and opens week detail', (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(23, 4),
    );

    await tester.pumpWidget(appFor(host));

    expect(find.text('۲۳'), findsOneWidget);
    expect(find.text('هفته و ۴ روز'), findsOneWidget);
    await tester.tap(find.text('جزئیات این هفته را ببین'));
    await tester.pumpAndSettle();
    expect(find.text('هفته ۲۳'), findsOneWidget);
  });

  testWidgets('compact phone with large text keeps pregnancy home scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('en'),
      pregnancySnapshot: _pregnancyAtWeek(23, 4),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: appFor(host),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  testWidgets('calendar presents gestational timeline without invented events',
      (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(23, 4),
    );

    await tester.pumpWidget(appFor(host));
    await tester.tap(find.text('تقویم'));
    await tester.pumpAndSettle();

    expect(find.text('مسیر بارداری'), findsOneWidget);
    expect(find.text('هفته‌ی ۲۳ و روز ۴'), findsOneWidget);
    expect(find.text('برنامه‌ای ثبت نشده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick check-in supports selection and external submission', (
    tester,
  ) async {
    CocoonCheckInDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CocoonQuickCheckInScreen(
              fa: true,
              syncState: CocoonCheckInSyncState.idle,
              onSubmit: (draft) async => submitted = draft,
            ),
          ),
        ),
      ),
    );

    expect(find.text('یک مکث کوتاه برای خودت'), findsOneWidget);
    expect(find.text('ثبت حال امروز'), findsOneWidget);
    await tester.tap(find.text('آرام و خوب'));
    await tester.tap(find.text('معمولی'));
    await tester.pump();
    await tester.ensureVisible(find.text('ثبت حال امروز'));
    await tester.tap(find.text('ثبت حال امروز'));
    await tester.pump();

    expect(submitted?.feeling, CocoonCheckInFeeling.comfortable);
    expect(submitted?.energy, CocoonCheckInEnergy.steady);
  });

  testWidgets('queued check-in is not presented as server confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Scaffold(
          body: CocoonQuickCheckInScreen(
            fa: false,
            syncState: CocoonCheckInSyncState.queued,
            onSubmit: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Queued; not yet server-confirmed'), findsOneWidget);
    expect(find.text('Saved and server-confirmed'), findsNothing);
  });

  testWidgets('appointments distinguish cached pending-sync state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Scaffold(
          body: CocoonAppointmentsScreen(
            fa: true,
            offline: true,
            items: const [
              CocoonAppointmentViewData(
                id: 'appointment-1',
                title: 'ویزیت دوره‌ای',
                dateLabel: 'سه‌شنبه ۱۸ شهریور',
                timeLabel: '۱۶:۳۰',
                status: CocoonAppointmentStatus.pendingSync,
                cached: true,
              ),
            ],
            onAdd: _noop,
            onOpen: (_) {},
            onRetry: _noop,
          ),
        ),
      ),
    );

    expect(find.text('در انتظار همگام‌سازی'), findsOneWidget);
    expect(
      find.text('نسخه‌ی ذخیره‌شده؛ وضعیت آنلاین تأیید نشده'),
      findsOneWidget,
    );
    expect(find.text('پیش رو'), findsNothing);
  });

  testWidgets('appointments empty state has one clear add action', (
    tester,
  ) async {
    var requested = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Scaffold(
          body: CocoonAppointmentsScreen(
            fa: false,
            items: const [],
            onAdd: () => requested = true,
            onOpen: (_) {},
            onRetry: _noop,
          ),
        ),
      ),
    );

    expect(find.text('No appointments yet'), findsOneWidget);
    await tester.tap(find.text('Add appointment'));
    expect(requested, isTrue);
  });

  testWidgets('appointment form validates before external submission', (
    tester,
  ) async {
    CocoonAppointmentDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonAppointmentFormScreen(
          fa: true,
          submitState: CocoonAppointmentSubmitState.idle,
          initialDateLabel: '۱۸ شهریور',
          initialTimeLabel: '۱۶:۳۰',
          onPickDate: () async => '۱۸ شهریور',
          onPickTime: () async => '۱۶:۳۰',
          onSubmit: (draft) async => submitted = draft,
        ),
      ),
    );

    await tester.tap(find.text('ثبت قرار'));
    await tester.pump();
    expect(find.text('یک عنوان روشن وارد کن'), findsOneWidget);
    expect(submitted, isNull);

    await tester.enterText(find.byType(TextField).first, 'ویزیت دوره‌ای');
    await tester.tap(find.text('ثبت قرار'));
    await tester.pump();
    expect(submitted?.title, 'ویزیت دوره‌ای');
    expect(submitted?.reminderMinutes, 30);
  });

  testWidgets('cached appointment detail blocks mutation actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonAppointmentDetailScreen(
          fa: true,
          canMutate: false,
          data: const CocoonAppointmentDetailViewData(
            appointment: CocoonAppointmentViewData(
              id: 'appointment-1',
              title: 'ویزیت دوره‌ای',
              dateLabel: '۱۸ شهریور',
              timeLabel: '۱۶:۳۰',
              status: CocoonAppointmentStatus.scheduled,
              cached: true,
            ),
            reminderLabel: '۳۰ دقیقه قبل',
          ),
          onEdit: _noop,
          onCancel: () async {},
        ),
      ),
    );

    expect(find.text('جزئیات قرار'), findsOneWidget);
    expect(find.textContaining('نسخه‌ی ذخیره‌شده'), findsOneWidget);
    final cancel = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'لغو قرار'),
    );
    expect(cancel.onPressed, isNull);
  });

  testWidgets('pregnancy onboarding activates only after review', (
    tester,
  ) async {
    CocoonPregnancySetupDraft? submitted;
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: CocoonPregnancyOnboardingScreen(
            fa: true,
            timezone: 'Asia/Tehran',
            onPickDate: (_) async => CocoonPregnancyDateSelection(
              value: DateTime(2026, 9, 7),
              displayLabel: '۱۶ شهریور ۱۴۰۵',
              semanticLabel: 'شانزدهم شهریور ۱۴۰۵',
            ),
            onActivate: (draft) async {
              submitted = draft;
              return false;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تاریخ احتمالی زایمان'));
    await tester.pump();
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انتخاب تاریخ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ادامه'));
    await tester.pumpAndSettle();

    expect(find.text('یک مرور کوتاه'), findsOneWidget);
    await tester.tap(find.text('شروع همراهی من'));
    await tester.pumpAndSettle();
    expect(submitted?.datingSource, CocoonDatingSource.estimatedDueDate);
    expect(submitted?.timezone, 'Asia/Tehran');
    expect(find.textContaining('فعال‌سازی انجام نشد'), findsOneWidget);
  });

  testWidgets('education tab shows only registry-approved weekly content', (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(4, 2),
    );
    await tester.pumpWidget(appFor(host));
    await tester.tap(find.text('آموزش'));
    await tester.pumpAndSettle();

    expect(find.text('راهنمای این هفته'), findsOneWidget);
    expect(find.text('هفته ۴'), findsWidgets);
    expect(find.text('بازبینی بالینی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('records keep cached timeline visible after refresh error', (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(4, 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonMateModule(
          config: CocoonModuleConfig(
            host: host,
            recordsState: CocoonRecordsState.error,
            records: const [
              CocoonRecordViewData(
                id: 'checkin-1',
                title: 'حال روزانه',
                dateLabel: 'امروز، ۹:۳۰',
                sectionLabel: 'امروز',
                summary: 'آرام و خوب',
                kind: CocoonRecordKind.checkIn,
                syncState: CocoonRecordSyncState.cached,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('سوابق'));
    await tester.pumpAndSettle();

    expect(find.text('حال روزانه'), findsWidgets);
    expect(find.text('ذخیره‌شده روی دستگاه'), findsOneWidget);
    expect(find.textContaining('به‌روزرسانی انجام نشد'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick add opens the owned check-in flow', (tester) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(4, 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonMateModule(
          config: CocoonModuleConfig(
            host: host,
            initialTab: 2,
            onSubmitCheckIn: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('یک ثبت ساده و آرام'), findsOneWidget);
    await tester.tap(find.text('حال امروز'));
    await tester.pumpAndSettle();
    expect(find.text('یک مکث کوتاه برای خودت'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick add exposes only an injected approved symptom catalog', (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(4, 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonMateModule(
          config: CocoonModuleConfig(
            host: host,
            initialTab: 2,
            symptomOptions: const [
              CocoonSymptomOption(
                id: 'approved-nausea',
                label: 'تهوع',
                icon: Icons.healing_outlined,
              ),
            ],
            onSubmitSymptom: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('نشانه یا علامت'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت نشانه'), findsWidgets);
    expect(find.text('تهوع'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('measurement form is driven by injected field and unit schema', (
    tester,
  ) async {
    final host = FakeHost(
      CocoonEntryState.activePregnancy,
      const Locale('fa'),
      pregnancySnapshot: _pregnancyAtWeek(4, 2),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonMateModule(
          config: CocoonModuleConfig(
            host: host,
            initialTab: 2,
            measurementOptions: const [
              CocoonMeasurementOption(
                id: 'weight',
                label: 'وزن',
                icon: Icons.monitor_weight_outlined,
                fields: [
                  CocoonMeasurementFieldSpec(
                    id: 'value',
                    label: 'وزن امروز',
                    unit: 'kg',
                  ),
                ],
              ),
            ],
            onSubmitMeasurement: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('اندازه‌گیری'));
    await tester.pumpAndSettle();
    expect(find.text('ثبت اندازه‌گیری'), findsWidgets);
    expect(find.text('وزن'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('medication log only presents injected care-plan items', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonMedicationLogScreen(
          fa: true,
          options: const [
            CocoonMedicationOption(
              id: 'care-plan-item',
              name: 'مکمل برنامه مراقبتی',
              doseLabel: 'طبق دستور ثبت‌شده',
            ),
          ],
          initialTimeLabel: '۰۹:۳۰',
          submitState: CocoonMedicationSubmitState.idle,
          onPickTime: () async => '۱۰:۰۰',
          onSubmit: (_) async {},
        ),
      ),
    );

    expect(find.text('ثبت دارو و مکمل'), findsOneWidget);
    expect(find.text('مکمل برنامه مراقبتی'), findsOneWidget);
    expect(find.text('طبق دستور ثبت‌شده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reminder settings renders host-owned privacy preferences', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonReminderSettingsScreen(
          fa: true,
          loadState: CocoonReminderLoadState.ready,
          saveState: CocoonReminderSaveState.idle,
          data: const CocoonReminderSettingsViewData(
            preferences: CocoonReminderPreferences(
              weeklyUpdate: true,
              dailyCheckIn: true,
              lockScreenPrivacy: CocoonLockScreenPrivacy.private,
            ),
            permission: CocoonReminderPermissionState.granted,
            appointmentSummary: 'از تقویم مراقبتی',
            medicationSummary: 'از برنامه درمانی',
          ),
          onRetry: _noop,
          onSave: (_) async {},
          onOpenAppointments: _noop,
          onOpenMedications: _noop,
        ),
      ),
    );

    expect(find.text('یادآورها و حریم خصوصی'), findsOneWidget);
    expect(find.text('مرور هفتگی بارداری'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('safety renderer never needs client-side clinical rules', (
    tester,
  ) async {
    const copy = CocoonSafetyGuidanceCopy(
      eyebrow: 'ایمنی',
      pageTitle: 'راهنمای ایمنی',
      pageIntroduction: 'محتوای بازبینی‌شده',
      loadingLabel: 'در حال بارگذاری',
      unavailableTitle: 'راهنما در دسترس نیست',
      unavailableBody: 'از مسیر مراقبتی تأییدشده استفاده کن',
      unavailableActionLabel: 'تلاش دوباره',
      errorTitle: 'به‌روزرسانی انجام نشد',
      errorBody: 'اطلاعات جدید دریافت نشد',
      errorActionLabel: 'تلاش دوباره',
      offlineCachedLabel: 'نسخه ذخیره‌شده',
      reviewedLabel: 'بازبینی‌شده',
      ruleVersionLabel: 'نسخه قانون',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: CocoonSafetyGuidanceScreen(
          state: CocoonSafetyGuidanceLoadState.unavailable,
          copy: copy,
          onRetry: _noop,
          onGuidanceAction: (_) {},
        ),
      ),
    );

    expect(find.text('راهنما در دسترس نیست'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings renders canonical host summaries', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CocoonTheme.light(),
        home: Scaffold(
          body: CocoonSettingsScreen(
            fa: true,
            state: CocoonSettingsLoadState.ready,
            data: const CocoonSettingsViewData(
              pregnancyLabel: 'هفته ۲۴ و ۳ روز',
              dueDateLabel: 'موعد ثبت‌شده در پرونده',
              datingSourceLabel: 'سونوگرافی',
              remindersSummary: 'خصوصی',
              sharingSummary: 'بدون دسترسی فعال',
              languageLabel: 'فارسی',
              largeTextEnabled: false,
              reducedMotionEnabled: false,
              syncState: CocoonSettingsSyncState.synced,
              syncSummary: 'به‌روز',
              subscriptionSummary: 'مدیریت در LifeMate',
              supportSummary: 'بدون پیوست اطلاعات سلامت',
              privacyLegalSummary: 'تنظیمات مشترک LifeMate',
              globalProfileLabel: 'پروفایل اصلی',
            ),
            onRetry: _noop,
            onOpenPregnancyDating: _noop,
            onOpenReminders: _noop,
            onOpenPrivacySharing: _noop,
            onOpenLanguage: _noop,
            onOpenAccessibility: _noop,
            onReducedMotionChanged: (_) {},
            onOpenDataAndSync: _noop,
            onOpenSubscription: _noop,
            onOpenSupport: _noop,
            onOpenPrivacyLegal: _noop,
            onOpenGlobalProfile: _noop,
          ),
        ),
      ),
    );

    expect(find.text('هفته ۲۴ و ۳ روز'), findsOneWidget);
    expect(find.text('بارداری'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

CocoonPregnancySnapshot _pregnancyAtWeek(int week, int day) {
  final totalDays = week * 7 + day;
  return CocoonPregnancySnapshot(
    contractVersion: 1,
    episode: CocoonPregnancyEpisode(
      id: 'synthetic-episode',
      motherPersonId: 'synthetic-person',
      status: CocoonPregnancyEpisodeStatus.active,
      dating: CocoonPregnancyDating(
        method: null,
        lmpDate: null,
        estimatedDueDate: null,
        referenceDate: null,
        gestationalAgeAtReferenceDays: null,
        gestationalAge: CocoonGestationalAge(
          totalDays: totalDays,
          week: week,
          day: day,
          basis: 'server-derived',
        ),
      ),
      outcome: null,
      activatedAtUtc: null,
      endedAtUtc: null,
      version: 1,
      updatedAtUtc: null,
    ),
  );
}
