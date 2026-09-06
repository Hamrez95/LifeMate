// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

export 'health_record_screen.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<LifeMateApiClient>().getCurrentUser();
  }

  void _retry() => setState(
    () => _future = context.read<LifeMateApiClient>().getCurrentUser(),
  );

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اطلاعات شخصی',
          en: "Personal information",
        ),
        en: "Personal information",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اطلاعات حساب متصل به LifeMate',
          en: "Account information connected to LifeMate",
        ),
        en: "Account information connected to LifeMate",
      ),
      icon: Icons.person_rounded,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _LoadingCard();
          }
          if (snapshot.hasError) {
            return _ErrorCard(
              message: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اطلاعات حساب دریافت نشد.',
                  en: "Account information not received.",
                ),
                en: "Account information not received.",
              ),
              onRetry: _retry,
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final user = data['user'] as Map<String, dynamic>? ?? const {};
          final profile = data['profile'] as Map<String, dynamic>? ?? const {};
          return Column(
            children: [
              _SoftCard(
                child: Column(
                  children: [
                    _ProfileAvatar(icon: Icons.person_rounded),
                    SizedBox(height: 16),
                    _InformationRow(
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'نام نمایشی',
                          en: "display name",
                        ),
                        en: "display name",
                      ),
                      value: _value(profile['displayName']),
                      icon: Icons.badge_outlined,
                    ),
                    _InformationRow(
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'ایمیل',
                          en: "Email",
                        ),
                        en: "Email",
                      ),
                      value: _value(user['email'] ?? profile['email']),
                      icon: Icons.alternate_email_rounded,
                      ltr: true,
                    ),
                    _InformationRow(
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'شماره تماس',
                          en: "Contact number",
                        ),
                        en: "Contact number",
                      ),
                      value: _value(profile['phoneNumber']),
                      icon: Icons.phone_outlined,
                      ltr: true,
                    ),
                    _InformationRow(
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'زبان',
                          en: "language",
                        ),
                        en: "language",
                      ),
                      value: _value(profile['locale'], fallback: 'fa'),
                      icon: Icons.language_rounded,
                    ),
                    _InformationRow(
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'منطقه زمانی',
                          en: "time zone",
                        ),
                        en: "time zone",
                      ),
                      value: _value(
                        profile['timeZone'],
                        fallback: 'Asia/Tehran',
                      ),
                      icon: Icons.schedule_rounded,
                      ltr: true,
                      showDivider: false,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              _DevelopmentNotice(
                message: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'نمایش اطلاعات از حساب واقعی انجام می‌شود. ویرایش اطلاعات پس از اضافه‌شدن قرارداد امن Backend فعال خواهد شد.',
                    en: "Information is displayed from the real account. Data editing will be enabled after the backend secure contract is added.",
                  ),
                  en: "Information is displayed from the real account. Data editing will be enabled after the backend secure contract is added.",
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: null,
                  icon: Icon(Icons.edit_outlined),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'ویرایش اطلاعات — در دست توسعه',
                        en: "Editing information — under development",
                      ),
                      en: "Editing information — under development",
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Historical medication-adherence summary kept temporarily for route safety.
/// The private document-first record lives in health_record_screen.dart.
class LegacyHealthRecordSummaryScreen extends StatefulWidget {
  const LegacyHealthRecordSummaryScreen({super.key});

  @override
  State<LegacyHealthRecordSummaryScreen> createState() =>
      _LegacyHealthRecordSummaryScreenState();
}

class _LegacyHealthRecordSummaryScreenState
    extends State<LegacyHealthRecordSummaryScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final api = context.read<LifeMateApiClient>();
    final now = DateTime.now();
    return Future.wait<dynamic>([
      api.getTreatmentPlans(),
      api.getDoseOccurrences(fromDate: now, toDate: now),
    ]);
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'پرونده سلامت', en: "health file"),
        en: "health file",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'خلاصه درمان و پایبندی امروز',
          en: "Summary of treatment and adherence today",
        ),
        en: "Summary of treatment and adherence today",
      ),
      icon: Icons.assignment_rounded,
      accent: Colors.orangeAccent,
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _LoadingCard();
          }
          if (snapshot.hasError) {
            return _ErrorCard(
              message: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'خلاصه پرونده سلامت دریافت نشد.',
                  en: "The summary of the health record was not received.",
                ),
                en: "The summary of the health record was not received.",
              ),
              onRetry: _retry,
            );
          }
          final plans =
              snapshot.data?[0] as List<Map<String, dynamic>>? ??
              const <Map<String, dynamic>>[];
          final doses =
              snapshot.data?[1] as List<Map<String, dynamic>>? ??
              const <Map<String, dynamic>>[];
          final active = plans
              .where((plan) => plan['status'] == 'active')
              .length;
          final taken = doses.where((dose) => dose['status'] == 'taken').length;
          final skipped = doses
              .where((dose) => dose['status'] == 'skipped')
              .length;
          final missed = doses
              .where((dose) => dose['status'] == 'missed')
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      value: '$active',
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'درمان فعال',
                          en: "Active treatment",
                        ),
                        en: "Active treatment",
                      ),
                      icon: Icons.medication_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      value: '$taken',
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مصرف‌شده امروز',
                          en: "Consumed today",
                        ),
                        en: "Consumed today",
                      ),
                      icon: Icons.check_circle_rounded,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      value: '$skipped',
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مصرف‌نشده',
                          en: "not consumed",
                        ),
                        en: "not consumed",
                      ),
                      icon: Icons.remove_circle_outline_rounded,
                      color: Colors.orange,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      value: '$missed',
                      label: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'فراموش‌شده',
                          en: "forgotten",
                        ),
                        en: "forgotten",
                      ),
                      icon: Icons.error_outline_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'برنامه‌های درمان',
                    en: "Treatment plans",
                  ),
                  en: "Treatment plans",
                ),
                style: AppTextStyles.heading(context).copyWith(fontSize: 18),
              ),
              SizedBox(height: 12),
              if (plans.isEmpty)
                _EmptyCard(
                  icon: Icons.medication_liquid_rounded,
                  message: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'هنوز برنامه درمانی ثبت نشده است.',
                      en: "No treatment plan has been registered yet.",
                    ),
                    en: "No treatment plan has been registered yet.",
                  ),
                )
              else
                ...plans.map((plan) => _TreatmentSummaryCard(plan: plan)),
              SizedBox(height: 8),
              _DevelopmentNotice(
                message: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'این صفحه فقط داده‌های درمانی موجود در Backend را نشان می‌دهد. آزمایش‌ها، علائم حیاتی و اسناد پزشکی هنوز ذخیره نمی‌شوند.',
                    en: "This page only shows the treatment data available in the backend. Tests, vital signs, and medical records are not stored yet.",
                  ),
                  en: "This page only shows the treatment data available in the backend. Tests, vital signs, and medical records are not stored yet.",
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    final today = DateTime.now();
    return context.read<LifeMateApiClient>().getDoseOccurrences(
      fromDate: today,
      toDate: today,
    );
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'اعلان‌ها', en: "Notifications"),
        en: "Notifications",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'یادآوری‌ها و وضعیت برنامه امروز',
          en: "Today's app status and reminders",
        ),
        en: "Today's app status and reminders",
      ),
      icon: Icons.notifications_none_rounded,
      accent: AppColors.primaryBlue,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _LoadingCard();
          }
          if (snapshot.hasError) {
            return _ErrorCard(
              message: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اعلان‌های امروز دریافت نشدند.',
                  en: "Today's notifications were not received.",
                ),
                en: "Today's notifications were not received.",
              ),
              onRetry: _retry,
            );
          }
          final doses = List<Map<String, dynamic>>.from(
            snapshot.data ?? const <Map<String, dynamic>>[],
          );
          doses.sort((a, b) => _doseTime(a).compareTo(_doseTime(b)));
          if (doses.isEmpty) {
            return _EmptyCard(
              icon: Icons.notifications_off_outlined,
              message: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'برای امروز یادآوری دارویی وجود ندارد.',
                  en: "There are no medication reminders for today.",
                ),
                en: "There are no medication reminders for today.",
              ),
            );
          }
          return Column(
            children: doses
                .map((dose) => _NotificationDoseCard(dose: dose))
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'کد معرف',
          en: "Identification code",
        ),
        en: "Identification code",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'دعوت دوستان و اعضای خانواده',
          en: "Invite friends and family members",
        ),
        en: "Invite friends and family members",
      ),
      icon: Icons.card_giftcard_rounded,
      accent: Colors.redAccent,
      child: Column(
        children: [
          _SoftCard(
            child: Column(
              children: [
                _ProfileAvatar(icon: Icons.card_giftcard_rounded),
                SizedBox(height: 18),
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'کد معرف شما',
                      en: "Your identification code",
                    ),
                    en: "Your identification code",
                  ),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 10),
                Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'پس از فعال‌شدن سرویس دعوت، کد اختصاصی در این قسمت نمایش داده می‌شود.',
                      en: "After activating the invitation service, the exclusive code will be displayed in this section.",
                    ),
                    en: "After activating the invitation service, the exclusive code will be displayed in this section.",
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.7, color: AppColors.textSecondary),
                ),
                SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.share_outlined),
                    label: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'اشتراک‌گذاری — در دست توسعه',
                          en: "Sharing — under development",
                        ),
                        en: "Sharing — under development",
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          _DevelopmentNotice(
            message: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تا زمان آماده‌شدن Backend معرفی و پاداش، هیچ کد ساختگی تولید یا نمایش داده نمی‌شود.',
                en: "No dummy code will be generated or displayed until the referral and reward backend is ready.",
              ),
              en: "No dummy code will be generated or displayed until the referral and reward backend is ready.",
            ),
          ),
        ],
      ),
    );
  }
}

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'پشتیبانی', en: "Support"),
        en: "Support",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'راهنما و ارتباط با تیم LifeMate',
          en: "Help and communication with the LifeMate team",
        ),
        en: "Help and communication with the LifeMate team",
      ),
      icon: Icons.support_agent_rounded,
      accent: Colors.indigo,
      child: Column(
        children: [
          _SupportTile(
            icon: Icons.help_outline_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'چطور یک درمان اضافه کنم؟',
                en: "How do I add a treatment?",
              ),
              en: "How do I add a treatment?",
            ),
            description: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'از نوار پایین وارد «افزودن درمان» شوید، نام دارو، مقدار و زمان مصرف را ثبت کنید.',
                en: "Enter \"add treatment\" from the bottom bar, record the drug name, amount and time of administration.",
              ),
              en: "Enter \"add treatment\" from the bottom bar, record the drug name, amount and time of administration.",
            ),
          ),
          SizedBox(height: 12),
          _SupportTile(
            icon: Icons.family_restroom_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'چطور مراقب اضافه کنم؟',
                en: "How do I add care?",
              ),
              en: "How do I add care?",
            ),
            description: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'در پروفایل وارد بخش «مراقبان» شوید و دعوت امن را برای فرد موردنظر بسازید.',
                en: "Enter the \"Caregivers\" section in the profile and create a safe invitation for the desired person.",
              ),
              en: "Enter the \"Caregivers\" section in the profile and create a safe invitation for the desired person.",
            ),
          ),
          SizedBox(height: 12),
          _SupportTile(
            icon: Icons.lock_outline_rounded,
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'حریم خصوصی چگونه حفظ می‌شود؟',
                en: "How is privacy maintained?",
              ),
              en: "How is privacy maintained?",
            ),
            description: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'دسترسی مراقب فقط با رضایت شما ایجاد می‌شود و هر زمان قابل لغو است.',
                en: "Caregiver access is only established with your consent and can be revoked at any time.",
              ),
              en: "Caregiver access is only established with your consent and can be revoked at any time.",
            ),
          ),
          SizedBox(height: 16),
          _DevelopmentNotice(
            message: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'کانال تیکت و گفت‌وگوی پشتیبانی هنوز Backend ندارد؛ دکمه تماس تا آماده‌شدن مسیر رسمی غیرفعال است.',
                en: "The ticket and support chat channel does not have a backend yet; The call button is disabled until the official route is ready.",
              ),
              en: "The ticket and support chat channel does not have a backend yet; The call button is disabled until the official route is ready.",
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: null,
              icon: Icon(Icons.chat_bubble_outline_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ارتباط با پشتیبانی — در دست توسعه',
                    en: "Contact Support — under development",
                  ),
                  en: "Contact Support — under development",
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _profile = const {};

  bool get _enabled => _profile['enabled'] == true;
  int get _version =>
      _profile['version'] is int ? _profile['version'] as int : 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .getWomenCalendarProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      debugPrint('Subscription women calendar load failed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate() async {
    if (!LifeMateFeatureFlags.womenCalendarPilotEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'این قابلیت در Build فعلی فعال نیست.',
                en: "This feature is not enabled in the current build.",
              ),
              en: "This feature is not enabled in the current build.",
            ),
          ),
        ),
      );
      return;
    }
    final selected = await showAppDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'شروع آخرین دوره',
          en: "The beginning of the last period",
        ),
        en: "The beginning of the last period",
      ),
    );
    if (selected == null || !mounted) return;
    await _save(enabled: true, lastPeriodStart: selected);
  }

  Future<void> _deactivate() async {
    final currentStart = DateTime.tryParse(
      _profile['lastPeriodStart']?.toString() ?? '',
    );
    await _save(enabled: false, lastPeriodStart: currentStart);
  }

  Future<void> _save({
    required bool enabled,
    required DateTime? lastPeriodStart,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final profile = await context
          .read<LifeMateApiClient>()
          .updateWomenCalendarProfile(
            version: _version,
            enabled: enabled,
            lastPeriodStart: lastPeriodStart,
            cycleLength: _profile['cycleLength'] is int
                ? _profile['cycleLength'] as int
                : 28,
            periodLength: _profile['periodLength'] is int
                ? _profile['periodLength'] as int
                : 5,
            remindersEnabled: _profile['remindersEnabled'] != false,
          );
      if (!mounted) return;
      setState(() => _profile = profile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تقویم بانوان برای نسخه داخلی فعال شد.',
                      en: "Ladies calendar is activated for internal version.",
                    ),
                    en: "Ladies calendar is activated for internal version.",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تقویم بانوان غیرفعال شد.',
                      en: "The women's calendar was disabled.",
                    ),
                    en: "The women's calendar was disabled.",
                  ),
          ),
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'women_calendar_feature_disabled' => LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تقویم بانوان روی سرور این نسخه فعال نیست؛ نسخه جدید را نصب کنید.',
            en: "The women's calendar is not active on the server of this version; Install the new version.",
          ),
          en: "The women's calendar is not active on the server of this version; Install the new version.",
        ),
        'stale_women_calendar_profile' => LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تنظیمات تقویم تغییر کرده است؛ صفحه را تازه کنید و دوباره تلاش کنید.',
            en: "Calendar settings have changed; Refresh the page and try again.",
          ),
          en: "Calendar settings have changed; Refresh the page and try again.",
        ),
        _ when error.statusCode == 0 => LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اتصال برقرار نشد. اینترنت را بررسی و دوباره تلاش کنید.',
            en: "Connection failed. Check the internet and try again.",
          ),
          en: "Connection failed. Check the internet and try again.",
        ),
        _ => LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فعال‌سازی تقویم بانوان انجام نشد. دوباره تلاش کنید.',
            en: "The women's calendar was not activated. Try again.",
          ),
          en: "The women's calendar was not activated. Try again.",
        ),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (error) {
      debugPrint('Subscription women calendar save failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'فعال‌سازی انجام نشد. اتصال را بررسی کنید.',
                  en: "Activation failed. Check the connection.",
                ),
                en: "Activation failed. Check the connection.",
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WellMateDestinationScaffold(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اشتراک LifeMate',
          en: "LifeMate subscription",
        ),
        en: "LifeMate subscription",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'امکانات پایه و قابلیت‌های اختیاری',
          en: "Basic features and optional features",
        ),
        en: "Basic features and optional features",
      ),
      icon: Icons.emoji_events_rounded,
      accent: Colors.amber,
      child: Column(
        children: [
          _SubscriptionPlanCard(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'نسخه پایه',
                en: "Basic version",
              ),
              en: "Basic version",
            ),
            description: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'ثبت درمان، برنامه روزانه، اعلان محلی و اتصال امن یک مراقب',
                en: "Treatment log, daily schedule, local notification and secure connection of a caregiver",
              ),
              en: "Treatment log, daily schedule, local notification and secure connection of a caregiver",
            ),
            current: true,
            statusLabel: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'فعال', en: "active"),
              en: "active",
            ),
            buttonLabel: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'نسخه فعلی',
                en: "Current version",
              ),
              en: "Current version",
            ),
          ),
          SizedBox(height: 14),
          _SubscriptionPlanCard(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تقویم بانوان',
                en: "Women's Calendar",
              ),
              en: "Women's calendar",
            ),
            description: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تقویم شمسی، خط زمانی چرخه، ثبت شروع و پایان دوره و اشتراک‌گذاری اختیاری با مراقب',
                en: "Solar calendar, cycle timeline, period start and end recording and optional sharing with caregiver",
              ),
              en: "Solar calendar, cycle timeline, period start and end recording and optional sharing with caregiver",
            ),
            current: _enabled,
            statusLabel: _loading
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'در حال بررسی',
                      en: "under review",
                    ),
                    en: "under review",
                  )
                : _enabled
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(fa: 'فعال', en: "active"),
                    en: "active",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'غیرفعال',
                      en: "disabled",
                    ),
                    en: "disabled",
                  ),
            buttonLabel: _enabled
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'غیرفعال‌سازی',
                      en: "Deactivation",
                    ),
                    en: "Deactivation",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'فعال‌سازی آزمایشی',
                      en: "Test activation",
                    ),
                    en: "Test activation",
                  ),
            onPressed: _loading || _saving
                ? null
                : (_enabled ? _deactivate : _activate),
            accent: Color(0xFFD95B93),
          ),
          SizedBox(height: 14),
          _SubscriptionPlanCard(
            title: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'نسخه خانواده',
                en: "Family version",
              ),
              en: "Family version",
            ),
            description: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'گزارش‌های پیشرفته، چند مراقب، پرونده سلامت و پشتیبانی ویژه',
                en: "Advanced reports, multi-caregiver, health record and special support",
              ),
              en: "Advanced reports, multi-caregiver, health record and special support",
            ),
            current: false,
            statusLabel: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'در دست توسعه',
                en: "Under development",
              ),
              en: "Under development",
            ),
            buttonLabel: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'خرید — در دست توسعه',
                en: "Purchase — under development",
              ),
              en: "Purchase — under development",
            ),
          ),
          SizedBox(height: 16),
          _DevelopmentNotice(
            message: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'در این نسخه داخلی، فعال‌سازی تقویم بانوان آزمایشی است و هیچ پرداخت یا ارتباطی با درگاه بانکی انجام نمی‌شود.',
                en: "In this internal version, activation of ladies calendar is experimental and no payment or communication with banking portal is done.",
              ),
              en: "In this internal version, activation of ladies calendar is experimental and no payment or communication with banking portal is done.",
            ),
          ),
        ],
      ),
    );
  }
}

class _WellMateDestinationScaffold extends StatelessWidget {
  const _WellMateDestinationScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.accent = AppColors.primary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'بازگشت',
                        en: "Back",
                      ),
                      en: "return",
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_ios_new_rounded),
                    color: AppColors.darkBlue,
                  ),
                  SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            color: AppColors.darkBlue,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [child],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withOpacity(0.55),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 10,
            offset: Offset(-4, -4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.16),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(icon, color: AppColors.primary, size: 38),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.label,
    required this.value,
    required this.icon,
    this.ltr = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool ltr;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryBlue, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      textDirection: ltr ? TextDirection.ltr : null,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.09),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TreatmentSummaryCard extends StatelessWidget {
  const _TreatmentSummaryCard({required this.plan});
  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final medication = plan['medication'] as Map<String, dynamic>? ?? const {};
    final schedules = plan['schedules'] as List<dynamic>? ?? const [];
    final time = schedules.isEmpty
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'بدون زمان',
              en: "without time",
            ),
            en: "without time",
          )
        : _shortTime((schedules.first as Map<String, dynamic>)['localTime']);
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: _SoftCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.medication_rounded, color: AppColors.primary),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _value(
                      medication['name'],
                      fallback: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'دارو',
                          en: "Medication",
                        ),
                        en: "medicine",
                      ),
                    ),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '${_value(plan['doseText'])} • $time',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Chip(
              label: Text(
                plan['status'] == 'active'
                    ? LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'فعال',
                          en: "active",
                        ),
                        en: "active",
                      )
                    : LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'متوقف',
                          en: "stopped",
                        ),
                        en: "stopped",
                      ),
              ),
              backgroundColor: plan['status'] == 'active'
                  ? AppColors.primary.withOpacity(0.12)
                  : Colors.grey.shade100,
              side: BorderSide.none,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationDoseCard extends StatelessWidget {
  const _NotificationDoseCard({required this.dose});
  final Map<String, dynamic> dose;

  @override
  Widget build(BuildContext context) {
    final status = dose['status']?.toString() ?? 'scheduled';
    final style = _statusStyle(status);
    final medicationName = _value(
      dose['medicationName'],
      fallback: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'یادآوری دارو',
          en: "Medication reminder",
        ),
        en: "Medication reminder",
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SoftCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: style.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(style.icon, color: style.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medicationName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_doseTime(dose)} • ${_value(dose['doseText'])}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: style.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                style.label,
                style: TextStyle(
                  color: style.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  const _SupportTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  style: const TextStyle(
                    height: 1.65,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionPlanCard extends StatelessWidget {
  const _SubscriptionPlanCard({
    required this.title,
    required this.description,
    required this.current,
    required this.statusLabel,
    required this.buttonLabel,
    this.onPressed,
    this.accent = AppColors.primary,
  });

  final String title;
  final String description;
  final bool current;
  final String statusLabel;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  title ==
                          LifeMateRuntimeLocale.select(
                            fa: LifeMateRuntimeLocale.select(
                              fa: 'تقویم بانوان',
                              en: "Women's Calendar",
                            ),
                            en: "Women's calendar",
                          )
                      ? Icons.water_drop_rounded
                      : Icons.workspace_premium_rounded,
                  color: accent,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Chip(
                label: Text(statusLabel),
                side: BorderSide.none,
                backgroundColor: current
                    ? accent.withOpacity(0.12)
                    : Colors.amber.withOpacity(0.15),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(height: 1.7, color: AppColors.textSecondary),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _DevelopmentNotice extends StatelessWidget {
  const _DevelopmentNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.construction_rounded, color: Colors.amber.shade800),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(height: 1.65))),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const _SoftCard(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 44),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.error),
          SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.refresh_rounded),
            label: Text(
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
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            Icon(icon, size: 46, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _StatusStyle {
  const _StatusStyle(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

_StatusStyle _statusStyle(String status) => switch (status) {
  'taken' => _StatusStyle(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'مصرف شد', en: "Taken"),
      en: "was consumed",
    ),
    Icons.check_circle_rounded,
    Colors.green,
  ),
  'skipped' => _StatusStyle(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مصرف نشد',
        en: "It was not consumed",
      ),
      en: "It was not consumed",
    ),
    Icons.remove_circle_outline_rounded,
    Colors.orange,
  ),
  'missed' => _StatusStyle(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'فراموش شد', en: "It was forgotten"),
      en: "It was forgotten",
    ),
    Icons.error_outline_rounded,
    Colors.redAccent,
  ),
  _ => _StatusStyle(
    LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'برنامه‌ریزی‌شده', en: "planned"),
      en: "planned",
    ),
    Icons.schedule_rounded,
    AppColors.primaryBlue,
  ),
};

String _value(dynamic value, {String? fallback}) {
  final text = value?.toString().trim();
  final emptyValue =
      fallback ??
      LifeMateRuntimeLocale.select(fa: 'ثبت نشده', en: 'Not recorded');
  return text == null || text.isEmpty ? emptyValue : text;
}

String _shortTime(dynamic value) {
  final raw = value?.toString() ?? '';
  return raw.length >= 5 ? raw.substring(0, 5) : _value(raw);
}

String _doseTime(Map<String, dynamic> dose) =>
    _shortTime(dose['scheduledLocalTime']);
