import 'package:caremate/providers/care_notification_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('self reported completion copy preserves evidence semantics', () {
    final copy = CareNotificationProvider.completionCopy(
      const {
        'patientDisplayName': 'Mom',
        'medicationName': 'Metformin',
        'evidenceClass': 'self_reported',
      },
      isPersian: false,
    );

    expect(copy.body, 'Mom recorded Metformin as taken.');
    expect(copy.body, isNot(contains('Mom took Metformin')));
  });

  test('unknown evidence falls back to neutral completion wording', () {
    final copy = CareNotificationProvider.completionCopy(
      const {
        'patientDisplayName': 'Mom',
        'medicationName': 'Metformin',
        'evidenceClass': 'unknown',
      },
      isPersian: false,
    );

    expect(copy.body, 'A completion was recorded for Mom: Metformin.');
  });

  test('Persian self report uses relationship display name', () {
    final copy = CareNotificationProvider.completionCopy(
      const {
        'patientDisplayName': 'مامان جون',
        'medicationName': 'متفورمین',
        'evidenceClass': 'self_reported',
      },
      isPersian: true,
    );

    expect(copy.body, 'مامان جون ثبت کرد که متفورمین را مصرف کرده.');
  });
}
