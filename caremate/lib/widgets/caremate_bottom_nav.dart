import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../screens/care_event_management_screen.dart';

class CareMateBottomNav extends StatelessWidget {
  const CareMateBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isPersian =
        Provider.of<LocaleProvider>(context).locale.languageCode == 'fa';
    final fontFamily = isPersian ? 'Vazir' : 'Poppins';

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildNavItem(
              context: context,
              icon: Icons.calendar_month_rounded,
              label: loc['nav_calendar'],
              index: 0,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              context: context,
              icon: Icons.switch_account_rounded,
              label: loc['nav_profiles'],
              index: 1,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              context: context,
              icon: Icons.medical_services,
              label: loc['nav_add_new_threadment'],
              index: 2,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              context: context,
              icon: Icons.family_restroom_rounded,
              label: loc['nav_caring'],
              index: 3,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              context: context,
              icon: Icons.home_rounded,
              label: loc['nav_home'],
              index: 4,
              fontFamily: fontFamily,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int index,
    required String fontFamily,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected
        ? AppColors.primaryBlue
        : AppColors.secondaryText.withOpacity(0.5);

    return Expanded(
      child: Semantics(
        key: ValueKey<String>('caremate-nav-$index'),
        button: true,
        selected: isSelected,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (index == 2 && currentIndex != 2) {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder<void>(
                      pageBuilder: (_, __, ___) =>
                          const CareEventManagementScreen(),
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                    ),
                  );
                  return;
                }
                onTap(index);
              },
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 26, color: color),
                      const SizedBox(height: 4),
                      ExcludeSemantics(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: fontFamily,
                            fontSize: 10,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
