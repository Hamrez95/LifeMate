import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:wellmate/providers/grouped_medication_notification.dart';

void main() {
  const keys = <String>[
    'medication.optimization.nearby.title',
    'medication.optimization.nearby.info',
    'medication.optimization.nearby.applyTitle',
    'medication.optimization.nearby.applyDescription',
    'medication.optimization.nearby.confirmApply',
    'medication.optimization.nearby.undoAction',
    'medication.optimization.nearby.undoStale',
    'medication.optimization.nearby.noChanges',
    'medication.optimization.nearby.exactInterval',
    'medication.grouped.title',
    'medication.grouped.explanation',
    'medication.grouped.staleDose',
    'medication.grouped.saveFailed',
    'medication.grouped.notification.title',
    'medication.grouped.notification.emptyBody',
    'medication.grouped.notification.more',
    'medication.grouped.notification.reviewAction',
  ];

  test('nearby optimization keys are complete in English and Persian', () {
    for (final key in keys) {
      expect(
        lifeMateMessages.hasCompleteKey(key),
        isTrue,
        reason: 'Missing localized value for $key',
      );
    }
  });

  test('grouped notification copy is generated from the locale catalog', () {
    expect(groupedMedicationTitle(3, false), 'Time for 3 medications');
    expect(groupedMedicationTitle(3, true), 'وقت مصرف 3 دارو');
    expect(groupedMedicationReviewAction(false), 'Review medications');
    expect(groupedMedicationReviewAction(true), 'بررسی داروها');
  });

  test('parameter interpolation preserves exact interval copy', () {
    expect(
      lifeMateMessages.text(
        'medication.optimization.nearby.exactInterval',
        locale: const Locale('en'),
        params: const {'hours': 8},
      ),
      'The exact 8-hour interval remains unchanged.',
    );
    expect(
      lifeMateMessages.text(
        'medication.optimization.nearby.exactInterval',
        locale: const Locale('fa'),
        params: const {'hours': 8},
      ),
      'فاصله هر 8 ساعت بدون تغییر می‌ماند.',
    );
  });
}
