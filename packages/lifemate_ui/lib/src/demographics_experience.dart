import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'onboarding_components.dart';
import 'onboarding_theme.dart';

class LifeMateDemographicOnboardingGate extends StatefulWidget {
  const LifeMateDemographicOnboardingGate({
    super.key,
    required this.child,
    this.demographicsApi,
    this.onboardingApi,
  });

  final Widget child;
  final LifeMateDemographicsApi? demographicsApi;
  final LifeMateAccountOnboardingApi? onboardingApi;

  @override
  State<LifeMateDemographicOnboardingGate> createState() =>
      _LifeMateDemographicOnboardingGateState();
}

class _LifeMateDemographicOnboardingGateState
    extends State<LifeMateDemographicOnboardingGate> {
  late final LifeMateDemographicsApi _demographics =
      widget.demographicsApi ?? LifeMateDemographicsApi();
  late final LifeMateAccountOnboardingApi _onboarding =
      widget.onboardingApi ?? LifeMateAccountOnboardingApi.fromEnvironment();
  bool _loading = true;
  bool _saving = false;
  bool _passThrough = false;
  String? _error;
  LifeMateGenderIdentity? _gender;
  LifeMateSexAssignedAtBirth? _sex;
  final _selfDescription = TextEditingController();

  bool get _isPersian => LifeMateRuntimeLocale.isPersian;
  LifeMateOnboardingTheme get _theme => LifeMateOnboardingTheme.shared;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _onboarding.getSnapshot();
      if (profile.completed) {
        if (!mounted) return;
        setState(() {
          _passThrough = true;
          _loading = false;
        });
        return;
      }
      final demographic = await _demographics.getMine();
      if (!mounted) return;
      setState(() {
        _gender = demographic.genderIdentity == LifeMateGenderIdentity.notCollected
            ? null
            : demographic.genderIdentity;
        _sex = demographic.sexAssignedAtBirth ==
                LifeMateSexAssignedAtBirth.notCollected
            ? null
            : demographic.sexAssignedAtBirth;
        _selfDescription.text = demographic.genderSelfDescription ?? '';
        _passThrough = demographic.hasExplicitAnswer;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = LifeMateRuntimeLocale.select(
          fa: 'اطلاعات اولیه در دسترس نیست. دوباره تلاش کن.',
          en: 'Initial profile information is unavailable. Try again.',
        );
      });
    }
  }

  Future<void> _save() async {
    final gender = _gender;
    final sex = _sex;
    if (gender == null || sex == null || _saving) return;
    if (gender == LifeMateGenderIdentity.selfDescribe &&
        _selfDescription.text.trim().isEmpty) {
      setState(() => _error = LifeMateRuntimeLocale.select(
            fa: 'لطفاً توضیح کوتاهی برای جنسیت وارد کن.',
            en: 'Please enter a short gender description.',
          ));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _demographics.saveMine(
        genderIdentity: gender,
        genderSelfDescription: _selfDescription.text,
        sexAssignedAtBirth: sex,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _passThrough = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = LifeMateRuntimeLocale.select(
          fa: 'ذخیره انجام نشد. اتصال را بررسی و دوباره تلاش کن.',
          en: 'Could not save. Check your connection and try again.',
        );
      });
    }
  }

  @override
  void dispose() {
    _selfDescription.dispose();
    if (widget.onboardingApi == null) _onboarding.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_passThrough) return widget.child;
    if (_loading) {
      return _scaffold(
        primaryLabel:
            LifeMateRuntimeLocale.select(fa: 'در حال آماده‌سازی', en: 'Preparing'),
        primaryBusy: true,
        body: _question(
          title: LifeMateRuntimeLocale.select(
            fa: 'پروفایل شخصی تو را آماده می‌کنیم',
            en: 'Preparing your personal profile',
          ),
          description: LifeMateRuntimeLocale.select(
            fa: 'چند لحظه صبر کن.',
            en: 'This only takes a moment.',
          ),
        ),
      );
    }
    if (_error != null && _gender == null && _sex == null) {
      return _scaffold(
        primaryLabel: LifeMateRuntimeLocale.select(fa: 'تلاش دوباره', en: 'Try again'),
        onPrimary: _load,
        body: _question(
          title: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات پروفایل در دسترس نیست',
            en: 'Profile information is unavailable',
          ),
          description: _error!,
        ),
      );
    }
    return _scaffold(
      progress: 0.34,
      progressLabel: LifeMateRuntimeLocale.select(fa: 'اطلاعات پایه', en: 'Basic profile'),
      primaryLabel: LifeMateRuntimeLocale.select(fa: 'ذخیره و ادامه', en: 'Save and continue'),
      onPrimary: _gender == null || _sex == null || _saving ? null : _save,
      primaryBusy: _saving,
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          _question(
            title: LifeMateRuntimeLocale.select(
              fa: 'چطور خودت را معرفی می‌کنی؟',
              en: 'How do you describe your gender?',
            ),
            description: LifeMateRuntimeLocale.select(
              fa: 'برای شخصی‌سازی پیام‌ها استفاده می‌شود. همیشه می‌توانی «ترجیح می‌دهم نگویم» را انتخاب کنی.',
              en: 'Used for appropriate personalization. You can always choose “Prefer not to say”.',
            ),
          ),
          const SizedBox(height: 18),
          ..._genderOptions().map((option) => _choice(
                selected: _gender == option.$1,
                label: option.$2,
                onTap: () => setState(() {
                  _gender = option.$1;
                  if (_gender != LifeMateGenderIdentity.selfDescribe) {
                    _selfDescription.clear();
                  }
                  _error = null;
                }),
              )),
          if (_gender == LifeMateGenderIdentity.selfDescribe) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('demographic-self-description'),
              controller: _selfDescription,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: 'توضیح کوتاه',
                  en: 'Short description',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            LifeMateRuntimeLocale.select(
              fa: 'جنس ثبت‌شده هنگام تولد',
              en: 'Sex assigned at birth',
            ),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            LifeMateRuntimeLocale.select(
              fa: 'این مورد فقط برای تجربه‌های سلامت که واقعاً به آن نیاز دارند استفاده می‌شود و برای جنسیت پیام‌رسانی جایگزین نمی‌شود.',
              en: 'Used only for health experiences that genuinely need it. It is not used as a substitute for gender in messaging.',
            ),
            style: TextStyle(color: Colors.black.withValues(alpha: 0.58), height: 1.45),
          ),
          const SizedBox(height: 12),
          ..._sexOptions().map((option) => _choice(
                selected: _sex == option.$1,
                label: option.$2,
                onTap: () => setState(() {
                  _sex = option.$1;
                  _error = null;
                }),
              )),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _scaffold({
    required String primaryLabel,
    required Widget body,
    VoidCallback? onPrimary,
    bool primaryBusy = false,
    double? progress,
    String? progressLabel,
  }) {
    return Directionality(
      textDirection: _isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: LifeMateOnboardingScaffold(
        theme: _theme,
        title: LifeMateRuntimeLocale.select(fa: 'شروع LifeMate', en: 'Start LifeMate'),
        primaryLabel: primaryLabel,
        onPrimary: onPrimary,
        primaryBusy: primaryBusy,
        progress: progress,
        progressLabel: progressLabel,
        body: body,
      ),
    );
  }

  Widget _question({required String title, required String description}) =>
      LifeMateOnboardingQuestion(
        theme: _theme,
        title: title,
        description: description,
        icon: Icons.badge_outlined,
        alignCenter: true,
      );

  Widget _choice({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected
                    ? _theme.accent.withValues(alpha: 0.10)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? _theme.accent
                      : Colors.black.withValues(alpha: 0.08),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: selected ? _theme.accent : Colors.black38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  List<(LifeMateGenderIdentity, String)> _genderOptions() => [
        (LifeMateGenderIdentity.woman, LifeMateRuntimeLocale.select(fa: 'زن', en: 'Woman')),
        (LifeMateGenderIdentity.man, LifeMateRuntimeLocale.select(fa: 'مرد', en: 'Man')),
        (LifeMateGenderIdentity.nonBinary, LifeMateRuntimeLocale.select(fa: 'نان‌باینری', en: 'Non-binary')),
        (LifeMateGenderIdentity.selfDescribe, LifeMateRuntimeLocale.select(fa: 'خودم توضیح می‌دهم', en: 'Self-describe')),
        (LifeMateGenderIdentity.preferNotToSay, LifeMateRuntimeLocale.select(fa: 'ترجیح می‌دهم نگویم', en: 'Prefer not to say')),
      ];

  List<(LifeMateSexAssignedAtBirth, String)> _sexOptions() => [
        (LifeMateSexAssignedAtBirth.female, LifeMateRuntimeLocale.select(fa: 'مونث', en: 'Female')),
        (LifeMateSexAssignedAtBirth.male, LifeMateRuntimeLocale.select(fa: 'مذکر', en: 'Male')),
        (LifeMateSexAssignedAtBirth.intersex, LifeMateRuntimeLocale.select(fa: 'اینترسکس', en: 'Intersex')),
        (LifeMateSexAssignedAtBirth.preferNotToSay, LifeMateRuntimeLocale.select(fa: 'ترجیح می‌دهم نگویم', en: 'Prefer not to say')),
      ];
}

class LifeMateDemographicsEditorScreen extends StatefulWidget {
  const LifeMateDemographicsEditorScreen({
    super.key,
    this.api,
    required this.accent,
    required this.background,
  });

  final LifeMateDemographicsApi? api;
  final Color accent;
  final Color background;

  @override
  State<LifeMateDemographicsEditorScreen> createState() =>
      _LifeMateDemographicsEditorScreenState();
}

class _LifeMateDemographicsEditorScreenState
    extends State<LifeMateDemographicsEditorScreen> {
  late final LifeMateDemographicsApi _api = widget.api ?? LifeMateDemographicsApi();
  LifeMateDemographics? _value;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await _api.getMine();
      if (!mounted) return;
      setState(() {
        _value = value;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = LifeMateRuntimeLocale.select(
          fa: 'بارگذاری اطلاعات انجام نشد.',
          en: 'Could not load profile information.',
        );
      });
    }
  }

  Future<void> _edit() async {
    final current = _value;
    if (current == null) return;
    final result = await Navigator.of(context).push<LifeMateDemographics>(
      MaterialPageRoute(
        builder: (_) => _DemographicEditPage(
          api: _api,
          initial: current,
          accent: widget.accent,
          background: widget.background,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _value = result);
  }

  @override
  Widget build(BuildContext context) {
    final isPersian = LifeMateRuntimeLocale.isPersian;
    return Directionality(
      textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: widget.background,
        appBar: AppBar(
          backgroundColor: widget.background,
          title: Text(LifeMateRuntimeLocale.select(fa: 'جنسیت و اطلاعات پایه', en: 'Gender & demographics')),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: TextButton(onPressed: _load, child: Text(_error!)))
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _row(
                        LifeMateRuntimeLocale.select(fa: 'جنسیت', en: 'Gender'),
                        _genderLabel(_value!.genderIdentity),
                      ),
                      _row(
                        LifeMateRuntimeLocale.select(fa: 'جنس ثبت‌شده هنگام تولد', en: 'Sex assigned at birth'),
                        _sexLabel(_value!.sexAssignedAtBirth),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _edit,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(LifeMateRuntimeLocale.select(fa: 'ویرایش', en: 'Edit')),
                        style: FilledButton.styleFrom(backgroundColor: widget.accent),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _row(String title, String value) => Card(
        child: ListTile(title: Text(title), subtitle: Text(value)),
      );

  String _genderLabel(LifeMateGenderIdentity value) => switch (value) {
        LifeMateGenderIdentity.woman => LifeMateRuntimeLocale.select(fa: 'زن', en: 'Woman'),
        LifeMateGenderIdentity.man => LifeMateRuntimeLocale.select(fa: 'مرد', en: 'Man'),
        LifeMateGenderIdentity.nonBinary => LifeMateRuntimeLocale.select(fa: 'نان‌باینری', en: 'Non-binary'),
        LifeMateGenderIdentity.selfDescribe => _value?.genderSelfDescription ?? LifeMateRuntimeLocale.select(fa: 'خودتوصیف', en: 'Self-described'),
        LifeMateGenderIdentity.preferNotToSay => LifeMateRuntimeLocale.select(fa: 'ترجیح می‌دهم نگویم', en: 'Prefer not to say'),
        LifeMateGenderIdentity.notCollected => LifeMateRuntimeLocale.select(fa: 'ثبت نشده', en: 'Not collected'),
      };

  String _sexLabel(LifeMateSexAssignedAtBirth value) => switch (value) {
        LifeMateSexAssignedAtBirth.female => LifeMateRuntimeLocale.select(fa: 'مونث', en: 'Female'),
        LifeMateSexAssignedAtBirth.male => LifeMateRuntimeLocale.select(fa: 'مذکر', en: 'Male'),
        LifeMateSexAssignedAtBirth.intersex => LifeMateRuntimeLocale.select(fa: 'اینترسکس', en: 'Intersex'),
        LifeMateSexAssignedAtBirth.preferNotToSay => LifeMateRuntimeLocale.select(fa: 'ترجیح می‌دهم نگویم', en: 'Prefer not to say'),
        LifeMateSexAssignedAtBirth.notCollected => LifeMateRuntimeLocale.select(fa: 'ثبت نشده', en: 'Not collected'),
      };
}

class _DemographicEditPage extends StatefulWidget {
  const _DemographicEditPage({
    required this.api,
    required this.initial,
    required this.accent,
    required this.background,
  });
  final LifeMateDemographicsApi api;
  final LifeMateDemographics initial;
  final Color accent;
  final Color background;

  @override
  State<_DemographicEditPage> createState() => _DemographicEditPageState();
}

class _DemographicEditPageState extends State<_DemographicEditPage> {
  late LifeMateGenderIdentity _gender = widget.initial.genderIdentity == LifeMateGenderIdentity.notCollected
      ? LifeMateGenderIdentity.preferNotToSay
      : widget.initial.genderIdentity;
  late LifeMateSexAssignedAtBirth _sex = widget.initial.sexAssignedAtBirth == LifeMateSexAssignedAtBirth.notCollected
      ? LifeMateSexAssignedAtBirth.preferNotToSay
      : widget.initial.sexAssignedAtBirth;
  late final TextEditingController _description = TextEditingController(text: widget.initial.genderSelfDescription ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final value = await widget.api.saveMine(
        genderIdentity: _gender,
        genderSelfDescription: _description.text,
        sexAssignedAtBirth: _sex,
      );
      if (mounted) Navigator.of(context).pop(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LifeMateRuntimeLocale.select(fa: 'ذخیره انجام نشد', en: 'Could not save'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: widget.background,
        appBar: AppBar(
          backgroundColor: widget.background,
          title: Text(LifeMateRuntimeLocale.select(fa: 'ویرایش اطلاعات پایه', en: 'Edit demographics')),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            DropdownButtonFormField<LifeMateGenderIdentity>(
              value: _gender,
              decoration: InputDecoration(labelText: LifeMateRuntimeLocale.select(fa: 'جنسیت', en: 'Gender')),
              items: LifeMateGenderIdentity.values
                  .where((value) => value != LifeMateGenderIdentity.notCollected)
                  .map((value) => DropdownMenuItem(value: value, child: Text(_genderText(value))))
                  .toList(),
              onChanged: _saving ? null : (value) => setState(() => _gender = value!),
            ),
            if (_gender == LifeMateGenderIdentity.selfDescribe) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLength: 120,
                decoration: InputDecoration(labelText: LifeMateRuntimeLocale.select(fa: 'توضیح کوتاه', en: 'Short description')),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<LifeMateSexAssignedAtBirth>(
              value: _sex,
              decoration: InputDecoration(labelText: LifeMateRuntimeLocale.select(fa: 'جنس ثبت‌شده هنگام تولد', en: 'Sex assigned at birth')),
              items: LifeMateSexAssignedAtBirth.values
                  .where((value) => value != LifeMateSexAssignedAtBirth.notCollected)
                  .map((value) => DropdownMenuItem(value: value, child: Text(_sexText(value))))
                  .toList(),
              onChanged: _saving ? null : (value) => setState(() => _sex = value!),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: widget.accent),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(LifeMateRuntimeLocale.select(fa: 'ذخیره', en: 'Save')),
            ),
          ],
        ),
      );

  String _genderText(LifeMateGenderIdentity value) => switch (value) {
        LifeMateGenderIdentity.woman => LifeMateRuntimeLocale.select(fa: 'زن', en: 'Woman'),
        LifeMateGenderIdentity.man => LifeMateRuntimeLocale.select(fa: 'مرد', en: 'Man'),
        LifeMateGenderIdentity.nonBinary => LifeMateRuntimeLocale.select(fa: 'نان‌باینری', en: 'Non-binary'),
        LifeMateGenderIdentity.selfDescribe => LifeMateRuntimeLocale.select(fa: 'خودم توضیح می‌دهم', en: 'Self-describe'),
        LifeMateGenderIdentity.preferNotToSay => LifeMateRuntimeLocale.select(fa: 'ترجیح می‌دهم نگویم', en: 'Prefer not to say'),
        LifeMateGenderIdentity.notCollected => '',
      };

  String _sexText(LifeMateSexAssignedAtBirth value) => switch (value) {
        LifeMateSexAssignedAtBirth.female => LifeMateRuntimeLocale.select(fa: 'مونث', en: 'Female'),
        LifeMateSexAssignedAtBirth.male => LifeMateRuntimeLocale.select(fa: 'مذکر', en: 'Male'),
        LifeMateSexAssignedAtBirth.intersex => LifeMateRuntimeLocale.select(fa: 'اینترسکس', en: 'Intersex'),
        LifeMateSexAssignedAtBirth.preferNotToSay => LifeMateRuntimeLocale.select(fa: 'ترجیح می‌دهم نگویم', en: 'Prefer not to say'),
        LifeMateSexAssignedAtBirth.notCollected => '',
      };
}
