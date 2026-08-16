import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('conflict feedback requires refresh without exposing health context', () {
    final feedback = LifeMateOfflineSyncFeedback.fromResult(
      const LifeMateOfflineSyncResult(conflicts: 1),
    );

    expect(feedback.kind, LifeMateOfflineFeedbackKind.refreshRequired);
    expect(feedback.shouldNotify, true);
    expect(feedback.shouldRefresh, true);
    expect(feedback.titleFa, isNotEmpty);
    expect(feedback.titleEn, isNotEmpty);
    final text = '${feedback.titleFa} ${feedback.titleEn} '
        '${feedback.messageFa} ${feedback.messageEn}';
    expect(text, isNot(contains('account')));
    expect(text, isNot(contains('medication')));
    expect(text, isNot(contains('dose')));
    expect(text, isNot(contains('123e4567')));
  });

  test('retry feedback explains safe queued retry rather than data loss', () {
    final feedback = LifeMateOfflineSyncFeedback.fromResult(
      const LifeMateOfflineSyncResult(
        retainedForRetry: 1,
        pendingRemaining: 1,
      ),
    );

    expect(feedback.kind, LifeMateOfflineFeedbackKind.retryPending);
    expect(feedback.shouldNotify, true);
    expect(feedback.shouldRefresh, false);
    expect(feedback.messageFa, contains('ذخیره'));
    expect(feedback.messageEn, contains('same idempotent request'));
  });

  test('replayed feedback reports completion without duplicate semantics', () {
    final feedback = LifeMateOfflineSyncFeedback.fromResult(
      const LifeMateOfflineSyncResult(replayed: 1),
    );

    expect(feedback.kind, LifeMateOfflineFeedbackKind.replayed);
    expect(feedback.shouldNotify, true);
    expect(feedback.shouldRefresh, false);
    expect(feedback.messageFa, contains('تکراری'));
    expect(feedback.messageEn, contains('duplicate operation'));
  });

  test('empty result produces no user notice', () {
    final feedback = LifeMateOfflineSyncFeedback.fromResult(
      const LifeMateOfflineSyncResult(),
    );

    expect(feedback.kind, LifeMateOfflineFeedbackKind.noChange);
    expect(feedback.shouldNotify, false);
    expect(feedback.shouldRefresh, false);
    expect(feedback.messageFa, isEmpty);
    expect(feedback.messageEn, isEmpty);
  });
}
