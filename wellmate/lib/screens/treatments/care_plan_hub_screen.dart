import 'package:flutter/material.dart';

import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import 'add_treatment_screen.dart';
import 'care_event_form.dart';

class CarePlanHubScreen extends StatefulWidget {
  const CarePlanHubScreen({required this.onCreated, super.key});

  final VoidCallback onCreated;

  @override
  State<CarePlanHubScreen> createState() => _CarePlanHubScreenState();
}

class _CarePlanHubScreenState extends State<CarePlanHubScreen> {
  int _selectedIndex = 0;

  static const _headerHeight = 142.0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 54),
                child: TabbedAddTreatmentScreen(onCreated: widget.onCreated),
              ),
              Padding(
                padding: const EdgeInsets.only(top: _headerHeight),
                child: CareEventForm(
                  kind: CarePlanKind.appointment,
                  onCreated: widget.onCreated,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: _headerHeight),
                child: CareEventForm(
                  kind: CarePlanKind.injection,
                  onCreated: widget.onCreated,
                ),
              ),
            ],
          ),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 142,
          child: ColoredBox(color: AppColors.background),
        ),
        PositionedDirectional(
          top: 10,
          start: 20,
          end: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.add_task_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        LifeMateRuntimeLocale.select(
                          fa: 'افزودن برنامه مراقبت',
                          en: 'Add care plan',
                        ),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.darkBlue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _CareTypeSelector(
                  selectedIndex: _selectedIndex,
                  onChanged: (index) => setState(() => _selectedIndex = index),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CareTypeSelector extends StatelessWidget {
  const _CareTypeSelector({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String)>[
      (
        Icons.medication_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'درمان', en: "Treatment"),
          en: "treatment",
        ),
      ),
      (
        Icons.medical_services_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'ویزیت', en: "Appointment"),
          en: "visit",
        ),
      ),
      (
        Icons.vaccines_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تزریق', en: "Injection"),
          en: "Injection",
        ),
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.30),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final selected = selectedIndex == index;
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: item.$2,
                child: InkWell(
                  key: ValueKey<String>('wellmate-care-type-$index'),
                  borderRadius: BorderRadius.circular(17),
                  onTap: () => onChanged(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.$1,
                          size: 21,
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$2,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
