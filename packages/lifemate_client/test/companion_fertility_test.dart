import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  const engine = LifeMateCompanionFertilityEngine();

  LifeMateCompanionFertilityNotification? notification({
    bool view = true,
    bool receive = true,
    bool caregiver = true,
    bool reliable = true,
    String confidence = 'high',
    String pattern = 'regular',
    String state = 'inside_estimated_window',
    String windowStart = '2026-08-25',
    List<LifeMateCompanionFertilityHistoryItem> history = const [],
  }) => engine.notification(
    viewFertilityEstimate: view,
    receiveFertilityNotifications: receive,
    caregiverNotificationsEnabled: caregiver,
    state: state,
    estimatedWindowStartOn: windowStart,
    fertilityEstimateReliable: reliable,
    confidence: confidence,
    cyclePattern: pattern,
    history: history,
    locale: 'en',
  );

  test('fertility notification requires both independent owner opt-ins', () {
    expect(notification(view: false), isNull);
    expect(notification(receive: false), isNull);
  });

  test('caregiver notification preference cannot be bypassed', () {
    expect(notification(caregiver: false), isNull);
  });

  test('irregular low-confidence or unreliable estimates fail closed', () {
    expect(notification(pattern: 'variable'), isNull);
    expect(notification(confidence: 'low'), isNull);
    expect(notification(reliable: false), isNull);
  });

  test('notification only occurs while server projection says inside window', () {
    expect(notification(state: 'outside_estimated_window'), isNull);
    expect(notification(state: 'inside_estimated_window'), isNotNull);
  });

  test('one estimated window creates at most one stable notification', () {
    expect(
      notification(
        history: [
          LifeMateCompanionFertilityHistoryItem(
            guidanceId: 'notify.fertility.window.2026-08-25',
            shownAtUtc: DateTime.utc(2026, 8, 28),
          ),
        ],
      ),
      isNull,
    );
  });

  test('copy never claims confirmed ovulation or pregnancy probability', () {
    final copy = notification()!.fullBody.toLowerCase();
    expect(copy, contains('estimated'));
    expect(copy, contains('does not confirm ovulation'));
    expect(copy, isNot(contains('%')));
    expect(copy, isNot(contains('best time')));
    expect(copy, isNot(contains('guarantee')));
  });

  test('independent view scope can show a safe unavailable state', () {
    final insight = engine.insight(
      viewFertilityEstimate: true,
      state: 'unavailable',
      fertilityEstimateReliable: false,
      confidence: 'low',
      cyclePattern: 'insufficient_data',
      locale: 'en',
    );
    expect(insight?.state, LifeMateCompanionFertilityState.unavailable);
    expect(insight?.disclaimer.toLowerCase(), contains('contraception'));
  });

  test('without view opt-in no fertility insight is produced', () {
    expect(
      engine.insight(
        viewFertilityEstimate: false,
        state: 'inside_estimated_window',
        fertilityEstimateReliable: true,
        confidence: 'high',
        cyclePattern: 'regular',
        locale: 'en',
      ),
      isNull,
    );
  });

  test('guidance id uses estimated fertility window date not cycle start', () {
    expect(
      notification()?.guidanceId,
      'notify.fertility.window.2026-08-25',
    );
  });
}
