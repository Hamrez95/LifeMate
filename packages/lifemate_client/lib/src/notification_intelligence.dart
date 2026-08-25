enum LifeMateNotificationStage {
  reminder,
  alert,
  caregiverEscalation,
  completion,
  dailySummary,
}

enum LifeMateNotificationPriority { low, normal, high }

class LifeMateNotificationDecision {
  const LifeMateNotificationDecision({
    required this.stage,
    required this.priority,
    required this.deduplicationKey,
    required this.shouldNotify,
    required this.shouldCancel,
  });

  final LifeMateNotificationStage stage;
  final LifeMateNotificationPriority priority;
  final String deduplicationKey;
  final bool shouldNotify;
  final bool shouldCancel;
}

abstract final class LifeMateNotificationIntelligence {
  static const Duration defaultGracePeriod = Duration(minutes: 15);

  static String deduplicationKey({
    required String personId,
    required String sourceId,
    required LifeMateNotificationStage stage,
  }) {
    return '${stage.name}:${personId.trim()}:${sourceId.trim()}';
  }

  static LifeMateNotificationDecision evaluate({
    required String personId,
    required String sourceId,
    required String status,
    required DateTime scheduledAtUtc,
    required DateTime nowUtc,
    required LifeMateNotificationStage stage,
    Duration gracePeriod = defaultGracePeriod,
    bool relationshipAuthorized = true,
    bool preferenceEnabled = true,
    bool explicitHighPriority = false,
    bool digestEligible = false,
  }) {
    final normalizedStatus = status.trim().toLowerCase();
    final resolved = const <String>{
      'taken',
      'completed',
      'cancelled',
      'archived',
      'inactive',
      'stopped',
    }.contains(normalizedStatus);
    final key = deduplicationKey(
      personId: personId,
      sourceId: sourceId,
      stage: stage,
    );
    if (resolved) {
      return LifeMateNotificationDecision(
        stage: stage,
        priority: LifeMateNotificationPriority.normal,
        deduplicationKey: key,
        shouldNotify: false,
        shouldCancel: true,
      );
    }
    if (!preferenceEnabled ||
        (stage == LifeMateNotificationStage.caregiverEscalation &&
            !relationshipAuthorized)) {
      return LifeMateNotificationDecision(
        stage: stage,
        priority: LifeMateNotificationPriority.normal,
        deduplicationKey: key,
        shouldNotify: false,
        shouldCancel: true,
      );
    }

    final scheduled = scheduledAtUtc.toUtc();
    final now = nowUtc.toUtc();
    final scheduledReached = !now.isBefore(scheduled);
    final afterGrace = !now.isBefore(scheduled.add(gracePeriod));
    final missedState = scheduledReached &&
        (normalizedStatus == 'missed' ||
            normalizedStatus == 'skipped' ||
            (normalizedStatus == 'scheduled' && afterGrace));

    final shouldNotify = switch (stage) {
      LifeMateNotificationStage.reminder =>
        normalizedStatus == 'scheduled' && now.isBefore(scheduled),
      LifeMateNotificationStage.alert => missedState,
      LifeMateNotificationStage.caregiverEscalation => missedState,
      LifeMateNotificationStage.completion => false,
      LifeMateNotificationStage.dailySummary => digestEligible,
    };

    final priority = explicitHighPriority
        ? LifeMateNotificationPriority.high
        : digestEligible && stage == LifeMateNotificationStage.dailySummary
        ? LifeMateNotificationPriority.low
        : LifeMateNotificationPriority.normal;

    return LifeMateNotificationDecision(
      stage: stage,
      priority: priority,
      deduplicationKey: key,
      shouldNotify: shouldNotify,
      shouldCancel: !shouldNotify,
    );
  }

  static List<LifeMateNotificationDecision> deduplicate(
    Iterable<LifeMateNotificationDecision> decisions,
  ) {
    final byKey = <String, LifeMateNotificationDecision>{};
    for (final decision in decisions) {
      final existing = byKey[decision.deduplicationKey];
      if (existing == null || _rank(decision) > _rank(existing)) {
        byKey[decision.deduplicationKey] = decision;
      }
    }
    final result = byKey.values.toList(growable: false)
      ..sort(
        (left, right) =>
            left.deduplicationKey.compareTo(right.deduplicationKey),
      );
    return result;
  }

  static int _rank(LifeMateNotificationDecision decision) {
    if (decision.shouldCancel) return 3;
    return switch (decision.priority) {
      LifeMateNotificationPriority.high => 2,
      LifeMateNotificationPriority.normal => 1,
      LifeMateNotificationPriority.low => 0,
    };
  }
}
