import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/women_calendar/women_companion_daily_log_offline_policy.dart';

void main() {
  test('private create/update may queue only when sharing remains false', () {
    expect(
      WomenCompanionDailyLogOfflinePolicy.canQueuePrivateMutation(
        current: null,
        requestedShareWithCompanion: false,
      ),
      isTrue,
    );
    expect(
      WomenCompanionDailyLogOfflinePolicy.canQueuePrivateMutation(
        current: const <String, dynamic>{'shareSummaryWithCompanion': false},
        requestedShareWithCompanion: false,
      ),
      isTrue,
    );
  });

  test('offline queue cannot enable sharing or hide an online revocation', () {
    expect(
      WomenCompanionDailyLogOfflinePolicy.canQueuePrivateMutation(
        current: const <String, dynamic>{'shareSummaryWithCompanion': false},
        requestedShareWithCompanion: true,
      ),
      isFalse,
    );
    expect(
      WomenCompanionDailyLogOfflinePolicy.canQueuePrivateMutation(
        current: const <String, dynamic>{'shareSummaryWithCompanion': true},
        requestedShareWithCompanion: false,
      ),
      isFalse,
    );
  });

  test('unknown existing sharing state fails closed offline', () {
    for (final current in <Map<String, dynamic>>[
      const <String, dynamic>{},
      const <String, dynamic>{'shareSummaryWithCompanion': 'false'},
      const <String, dynamic>{'shareSummaryWithCompanion': null},
    ]) {
      expect(
        WomenCompanionDailyLogOfflinePolicy.canQueuePrivateMutation(
          current: current,
          requestedShareWithCompanion: false,
        ),
        isFalse,
      );
    }
  });

  test('only transient transport/server failures permit local fallback', () {
    for (final status in <int>[0, 408, 429, 500, 502, 503, 504]) {
      expect(
        WomenCompanionDailyLogOfflinePolicy.canQueueAfter(
          LifeMateApiException(
            statusCode: status,
            code: 'transient',
            message: 'transient',
          ),
        ),
        isTrue,
      );
    }
    for (final status in <int>[400, 401, 403, 409, 422]) {
      expect(
        WomenCompanionDailyLogOfflinePolicy.canQueueAfter(
          LifeMateApiException(
            statusCode: status,
            code: 'fail_closed',
            message: 'fail closed',
          ),
        ),
        isFalse,
      );
    }
  });
}
