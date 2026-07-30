import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../widgets/caremate_bottom_nav.dart';
import '../widgets/custom_app_header.dart';
import 'calendar/calendar_screen.dart';

/// Preserves the original CareMate navigation surface for features whose
/// backend contracts are not available yet. The page remains fully navigable
/// and visually complete, but unsupported controls are explicitly disabled.
class CareMateFeaturePreviewScreen extends StatefulWidget {
  const CareMateFeaturePreviewScreen({
    required this.initialIndex,
    super.key,
  }) : assert(initialIndex >= 1 && initialIndex <= 3);

  final int initialIndex;

  @override
  State<CareMateFeaturePreviewScreen> createState() =>
      _CareMateFeaturePreviewScreenState();
}

class _CareMateFeaturePreviewScreenState
    extends State<CareMateFeaturePreviewScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  _FeatureDefinition get _feature => switch (_currentIndex) {
        1 => const _FeatureDefinition(
            title: 'تغییر پروفایل',
            subtitle: 'مدیریت اعضای خانواده و انتخاب فرد تحت مراقبت',
            icon: Icons.switch_account_rounded,
            accent: Color(0xFF7B93DB),
            softBackground: Color(0xFFF2F4FF),
            sections: [
              _FeatureSection(
                title: 'اعضای خانواده',
                description:
                    'نمایش و ویرایش پروفایل اعضا پس از آماده‌شدن API پروفایل خانواده فعال می‌شود.',
                icon: Icons.family_restroom_rounded,
              ),
              _FeatureSection(
                title: 'سطح دسترسی',
                description:
                    'نقش‌ها و مجوزهای هر مراقب در این بخش مدیریت خواهند شد.',
                icon: Icons.admin_panel_settings_outlined,
              ),
            ],
          ),
        2 => const _FeatureDefinition(
            title: 'مدیریت درمان',
            subtitle: 'برنامه دارویی، ویزیت‌ها و روند درمان اعضای خانواده',
            icon: Icons.medical_services_rounded,
            accent: Color(0xFF5BA7E8),
            softBackground: Color(0xFFF0F8FF),
            sections: [
              _FeatureSection(
                title: 'برنامه‌های درمان',
                description:
                    'مشاهده و ویرایش برنامه درمان از سمت مراقب پس از تکمیل مجوزهای API فعال می‌شود.',
                icon: Icons.medication_liquid_rounded,
              ),
              _FeatureSection(
                title: 'ویزیت و آزمایش',
                description:
                    'ثبت و پیگیری نوبت‌ها در طراحی باقی مانده اما فعلاً قابل تغییر نیست.',
                icon: Icons.event_available_rounded,
              ),
            ],
          ),
        _ => const _FeatureDefinition(
            title: 'مراقبت خانواده',
            subtitle: 'هماهنگی مراقبان، هشدارها و پیگیری وضعیت خانواده',
            icon: Icons.family_restroom_rounded,
            accent: Color(0xFFE598D8),
            softBackground: Color(0xFFFFF3FC),
            sections: [
              _FeatureSection(
                title: 'تیم مراقبت',
                description:
                    'دعوت و لغو دسترسی مراقب از مسیرهای متصل فعلی انجام می‌شود؛ مدیریت کامل تیم در حال توسعه است.',
                icon: Icons.groups_rounded,
              ),
              _FeatureSection(
                title: 'گزارش خانوادگی',
                description:
                    'خلاصه هفتگی و اشتراک گزارش پس از آماده‌شدن سرویس گزارش فعال می‌شود.',
                icon: Icons.insights_rounded,
              ),
            ],
          ),
      };

  void _onNavigationTap(int index) {
    if (index == _currentIndex) return;
    if (index == 4) {
      Navigator.of(context).pop();
      return;
    }
    if (index == 0) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => const CalendarScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final feature = _feature;
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const CustomAppHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 130),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: feature.softBackground,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: feature.accent.withOpacity(0.12),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: feature.accent.withOpacity(0.15),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                          child: Icon(
                            feature.icon,
                            color: feature.accent,
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                feature.title,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryText,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                feature.subtitle,
                                style: const TextStyle(
                                  height: 1.55,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.amber.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.construction_rounded,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'این صفحه بخشی از طراحی اصلی محصول است. کنترل‌های بدون Backend فعلاً غیرفعال‌اند.',
                            style: TextStyle(height: 1.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...feature.sections.map(
                    (section) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _DisabledFeatureCard(
                        section: section,
                        accent: feature.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavigationTap,
      ),
    );
  }
}

class _DisabledFeatureCard extends StatelessWidget {
  const _DisabledFeatureCard({
    required this.section,
    required this.accent,
  });

  final _FeatureSection section;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppColors.softDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(section.icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'در دست توسعه',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  section.description,
                  style: const TextStyle(
                    height: 1.6,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('فعلاً غیرفعال'),
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

class _FeatureDefinition {
  const _FeatureDefinition({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.softBackground,
    required this.sections,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color softBackground;
  final List<_FeatureSection> sections;
}

class _FeatureSection {
  const _FeatureSection({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}
