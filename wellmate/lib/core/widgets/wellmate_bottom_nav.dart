import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../localization/app_localizations.dart';
import '../../localization/locale_provider.dart';
import '../theme/app_style.dart';
import 'package:lifemate_client/lifemate_client.dart';

class WellMateBottomNav extends StatelessWidget {
  const WellMateBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.womenCalendarEnabled = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool womenCalendarEnabled;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final isPersian =
        Provider.of<LocaleProvider>(context).locale.languageCode == 'fa';
    final fontFamily = isPersian ? 'Vazir' : 'Poppins';

    return SafeArea(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        padding: EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(35),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildNavItem(
              icon: Icons.calendar_month_rounded,
              label: loc['nav_calendar'],
              index: 0,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.medication_rounded,
              label: loc['nav_medications'],
              index: 1,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.add_circle_outline_rounded,
              label: loc['nav_add_treatment'],
              index: 2,
              fontFamily: fontFamily,
            ),
            _buildNavItem(
              icon: Icons.monitor_heart_rounded,
              label: isPersian
                  ? LifeMateRuntimeLocale.select(fa: 'سلامت', en: "Health")
                  : 'Health',
              index: 3,
              fontFamily: fontFamily,
            ),
            if (womenCalendarEnabled)
              _buildNavItem(
                icon: Icons.water_drop_rounded,
                label: isPersian
                    ? LifeMateRuntimeLocale.select(
                        fa: 'تقویم بانوان',
                        en: "Women's Calendar",
                      )
                    : 'Women',
                index: 4,
                fontFamily: fontFamily,
              ),
            _buildNavItem(
              icon: Icons.home_rounded,
              label: loc['nav_home'],
              index: 5,
              fontFamily: fontFamily,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required String fontFamily,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? AppColors.primary : Colors.grey.shade400;

    return Expanded(
      child: Semantics(
        key: ValueKey<String>('wellmate-nav-$index'),
        button: true,
        selected: isSelected,
        label: label,
        child: Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(index),
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 24, color: color),
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
                            fontSize: 9,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
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
