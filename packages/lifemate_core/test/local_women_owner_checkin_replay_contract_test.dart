import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  test('owner check-in replay omits rich-only and sharing fields', () {
    final mutation = LifeMateOfflineWomenDailyLogMutation.buildUpsert(
      mutationId: 'women-owner-replay-0001',
      loggedOn: DateTime(2026, 9, 6),
      version: 2,
      timeZone: 'Asia/Tehran',
      mood: 'good',
      energyLevel: 4,
      painLevel: 1,
      symptoms: const <String>{'Fatigue'},
      privateNotes: 'owner only',
    );

    expect(mutation.payload['mood'], 'good');
    expect(mutation.payload['energyLevel'], 4);
    expect(mutation.payload['symptoms'], <String>['fatigue']);
    expect(mutation.payload.containsKey('periodFlow'), isFalse);
    expect(mutation.payload.containsKey('bloodAppearance'), isFalse);
    expect(mutation.payload.containsKey('bloodTexture'), isFalse);
    expect(mutation.payload.containsKey('shareSummaryWithCompanion'), isFalse);
  });

  test('owner check-in cannot mix with rich period-only fields', () {
    expect(
      () => LifeMateOfflineWomenDailyLogMutation.buildUpsert(
        mutationId: 'women-owner-mixed-0001',
        loggedOn: DateTime(2026, 9, 6),
        version: 0,
        timeZone: 'Asia/Tehran',
        mood: 'good',
        energyLevel: 4,
        periodFlow: 'light',
      ),
      throwsArgumentError,
    );
  });
}
