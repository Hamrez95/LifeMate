import 'package:flutter/material.dart';

import '../../core/theme/app_style.dart';
import 'add_treatment_screen.dart';
import 'care_event_form.dart';
import 'package:lifemate_client/lifemate_client.dart';

class CarePlanHubScreen extends StatefulWidget {
  const CarePlanHubScreen({required this.onCreated, super.key});

  final VoidCallback onCreated;

  @override
  State<CarePlanHubScreen> createState() => _CarePlanHubScreenState();
}

class _CarePlanHubScreenState extends State<CarePlanHubScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              TabbedAddTreatmentScreen(onCreated: widget.onCreated),
              Padding(
                padding: const EdgeInsets.only(top: 78),
                child: CareEventForm(
                  kind: CarePlanKind.appointment,
                  onCreated: widget.onCreated,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 78),
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
          height: 78,
          child: ColoredBox(color: AppColors.background),
        ),
        Positioned(
          top: 8,
          left: 20,
          right: 20,
          child: _CareTypeSelector(
            selectedIndex: _selectedIndex,
            onChanged: (index) => setState(() => _selectedIndex = index),
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
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
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
                    constraints: const BoxConstraints(minHeight: 56),
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
