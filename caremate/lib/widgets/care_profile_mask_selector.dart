import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import 'package:lifemate_client/lifemate_client.dart';

class CareProfileMaskSelector extends StatefulWidget {
  const CareProfileMaskSelector({super.key});

  @override
  State<CareProfileMaskSelector> createState() =>
      _CareProfileMaskSelectorState();
}

class _CareProfileMaskSelectorState extends State<CareProfileMaskSelector> {
  String _selectedId = 'family';

  static final _activeProfiles = <_CareProfileDefinition>[
    _CareProfileDefinition(
      id: 'family',
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مراقبت از خانواده',
          en: "Family care",
        ),
        en: "Family care",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'برای مدیریت مراقبت چند عضو خانواده',
          en: "To manage the care of multiple family members",
        ),
        en: "To manage the care of multiple family members",
      ),
      icon: Icons.family_restroom_rounded,
      accent: Color(0xFF4A90E2),
      soft: Color(0xFFEAF4FF),
      capabilities: [
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برنامه درمان',
            en: "Treatment plan",
          ),
          en: "Treatment plan",
        ),
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تقویم', en: "Calendar"),
          en: "Calendar",
        ),
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'چند عضو',
            en: "How many members?",
          ),
          en: "How many members?",
        ),
      ],
    ),
    _CareProfileDefinition(
      id: 'spouse',
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مراقبت از همسر',
          en: "Caring for your wife",
        ),
        en: "Caring for your wife",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'برای همراهی روزانه و مراقبت مشترک',
          en: "For daily companionship and shared care",
        ),
        en: "For daily companionship and shared care",
      ),
      icon: Icons.favorite_rounded,
      accent: Color(0xFFE46D9C),
      soft: Color(0xFFFFEEF5),
      capabilities: [
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برنامه درمان',
            en: "Treatment plan",
          ),
          en: "Treatment plan",
        ),
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تقویم', en: "Calendar"),
          en: "Calendar",
        ),
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تقویم بانوان با اجازه',
            en: "Ladies calendar with permission",
          ),
          en: "Ladies calendar with permission",
        ),
      ],
    ),
    _CareProfileDefinition(
      id: 'child',
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مراقبت از فرزند',
          en: "Child care",
        ),
        en: "Child care",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'برای پیگیری درمان، ویزیت و تزریق',
          en: "To follow up treatment, visits and injections",
        ),
        en: "To follow up treatment, visits and injections",
      ),
      icon: Icons.child_care_rounded,
      accent: Color(0xFFF0A440),
      soft: Color(0xFFFFF6E8),
      capabilities: [
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
          en: "medicine",
        ),
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ویزیت و تزریق',
            en: "Visit and injection",
          ),
          en: "Visit and injection",
        ),
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تقویم', en: "Calendar"),
          en: "Calendar",
        ),
      ],
    ),
  ];

  static final _lockedProfiles = <_CareProfileDefinition>[
    _CareProfileDefinition(
      id: 'clinical',
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مراقبت از بیماران',
          en: "Caring for patients",
        ),
        en: "Caring for patients",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'پروفایل پزشک و پرستار',
          en: "Doctor and nurse profile",
        ),
        en: "Doctor and nurse profile",
      ),
      icon: Icons.medical_services_rounded,
      accent: Color(0xFF5A79C9),
      soft: Color(0xFFEEF2FF),
      capabilities: [],
      locked: true,
    ),
    _CareProfileDefinition(
      id: 'coach',
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مراقبت از شاگردان',
          en: "Caring for students",
        ),
        en: "Caring for students",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'پروفایل مربی‌های ورزشی',
          en: "Profile of sports coaches",
        ),
        en: "Profile of sports coaches",
      ),
      icon: Icons.fitness_center_rounded,
      accent: Color(0xFF7C8A94),
      soft: Color(0xFFF1F3F5),
      capabilities: [],
      locked: true,
    ),
  ];

  _CareProfileDefinition get _selected => _activeProfiles.firstWhere(
    (profile) => profile.id == _selectedId,
    orElse: () => _activeProfiles.first,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileIntroCard(),
        SizedBox(height: 22),
        _SectionLabel(
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پروفایل‌های فعال',
              en: "Active profiles",
            ),
            en: "Active profiles",
          ),
          subtitle: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'نقشی را انتخاب کنید که الان با آن از CareMate استفاده می‌کنید.',
              en: "Select the role you are currently using CareMate with.",
            ),
            en: "Select the role you are currently using CareMate with.",
          ),
        ),
        SizedBox(height: 12),
        ..._activeProfiles.map(
          (profile) => Padding(
            padding: EdgeInsets.only(bottom: 11),
            child: _ProfileMaskCard(
              profile: profile,
              selected: profile.id == _selectedId,
              onTap: () => setState(() => _selectedId = profile.id),
            ),
          ),
        ),
        SizedBox(height: 4),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _CapabilitiesCard(
            key: ValueKey<String>(_selected.id),
            profile: _selected,
          ),
        ),
        SizedBox(height: 26),
        _SectionLabel(
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'سایر پروفایل‌ها',
              en: "Other profiles",
            ),
            en: "Other profiles",
          ),
          subtitle: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'این نقش‌ها بعداً محیط و ابزارهای اختصاصی خودشان را خواهند داشت.',
              en: "These roles will later have their own dedicated environment and tools.",
            ),
            en: "These roles will later have their own dedicated environment and tools.",
          ),
        ),
        SizedBox(height: 12),
        ..._lockedProfiles.map(
          (profile) => Padding(
            padding: EdgeInsets.only(bottom: 11),
            child: _ProfileMaskCard(
              profile: profile,
              selected: false,
              onTap: null,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileIntroCard extends StatelessWidget {
  const _ProfileIntroCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFF3F7FF), Color(0xFFFFFFFF)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Color(0xFFDDE8F7)),
      boxShadow: [
        BoxShadow(
          color: Color(0x0B31547C),
          blurRadius: 22,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileIntroIcon(),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'یک حساب، چند نقش',
                    en: "One account, multiple roles",
                  ),
                  en: "One account, multiple roles",
                ),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryText,
                ),
              ),
              SizedBox(height: 6),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'LifeMate به‌مرور بر اساس نقشی که انتخاب می‌کنید چیدمان و ابزارهای مرتبط را نشان می‌دهد. فعلاً سه پروفایل خانوادگی فعال‌اند.',
                    en: "LifeMate will automatically display layouts and related tools based on the role you select. Currently, three family profiles are active.",
                  ),
                  en: "LifeMate will automatically display layouts and related tools based on the role you select. Currently, three family profiles are active.",
                ),
                style: TextStyle(
                  height: 1.6,
                  fontSize: 12.5,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProfileIntroIcon extends StatelessWidget {
  const _ProfileIntroIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
    ),
    child: const Icon(
      Icons.switch_account_rounded,
      color: AppColors.primaryBlue,
      size: 28,
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: AppColors.primaryText,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(
          height: 1.5,
          fontSize: 12.5,
          color: AppColors.secondaryText,
        ),
      ),
    ],
  );
}

class _ProfileMaskCard extends StatelessWidget {
  const _ProfileMaskCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final _CareProfileDefinition profile;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final locked = profile.locked;
    return Opacity(
      opacity: locked ? 0.62 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: selected ? profile.soft : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected
                    ? profile.accent.withValues(alpha: 0.52)
                    : const Color(0xFFE4EBF5),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: profile.accent.withValues(
                    alpha: selected ? 0.10 : 0.035,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: profile.soft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(profile.icon, color: profile.accent, size: 31),
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              profile.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primaryText,
                              ),
                            ),
                          ),
                          if (locked)
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Color(0xFFF0F2F5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                LifeMateRuntimeLocale.select(
                                  fa: LifeMateRuntimeLocale.select(
                                    fa: 'به‌زودی',
                                    en: "Coming soon",
                                  ),
                                  en: "soon",
                                ),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF8A949D),
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 5),
                      Text(
                        profile.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: locked
                        ? Color(0xFFF1F3F5)
                        : selected
                        ? profile.accent
                        : profile.soft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    locked
                        ? Icons.lock_outline_rounded
                        : selected
                        ? Icons.workspace_premium_rounded
                        : Icons.circle_outlined,
                    color: locked
                        ? Color(0xFF9DA5AC)
                        : selected
                        ? Colors.white
                        : profile.accent,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilitiesCard extends StatelessWidget {
  const _CapabilitiesCard({super.key, required this.profile});

  final _CareProfileDefinition profile;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: profile.soft,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'پروفایل فعال: ${profile.title}',
              en: "Active profile: ${profile.title}",
            ),
            en: "Active profile: ${profile.title}",
          ),
          key: ValueKey('care-profile-active-label'),
          style: TextStyle(fontWeight: FontWeight.w900, color: profile.accent),
        ),
        SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: profile.capabilities
              .map(
                (capability) => Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    capability,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    ),
  );
}

class _CareProfileDefinition {
  const _CareProfileDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.soft,
    required this.capabilities,
    this.locked = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color soft;
  final List<String> capabilities;
  final bool locked;
}
