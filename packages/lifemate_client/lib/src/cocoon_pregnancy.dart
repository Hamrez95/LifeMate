enum CocoonEnrollmentState { notEnrolled, draft, active, ended, unknown }

enum CocoonEntitlementState { active, inactive, unknown }

enum CocoonPregnancyEpisodeStatus { draft, active, ended, unknown }

enum CocoonApplicationAvailability { available, unavailable, unknown }

enum CocoonApplicationEnrollmentState {
  active,
  suspended,
  left,
  notEnrolled,
  unknown,
}

enum CocoonCommerceEligibilityState {
  entitled,
  conversionEligible,
  offerAvailable,
  notEntitled,
  unavailable,
  error,
  unknown,
}

CocoonEnrollmentState _enrollmentState(Object? value) => switch (value) {
  'not_enrolled' => CocoonEnrollmentState.notEnrolled,
  'draft' => CocoonEnrollmentState.draft,
  'active' => CocoonEnrollmentState.active,
  'ended' => CocoonEnrollmentState.ended,
  _ => CocoonEnrollmentState.unknown,
};

CocoonEntitlementState _entitlementState(Object? value) => switch (value) {
  'active' => CocoonEntitlementState.active,
  'inactive' => CocoonEntitlementState.inactive,
  _ => CocoonEntitlementState.unknown,
};

CocoonPregnancyEpisodeStatus _episodeStatus(Object? value) => switch (value) {
  'draft' => CocoonPregnancyEpisodeStatus.draft,
  'active' => CocoonPregnancyEpisodeStatus.active,
  'ended' => CocoonPregnancyEpisodeStatus.ended,
  _ => CocoonPregnancyEpisodeStatus.unknown,
};

CocoonApplicationAvailability _applicationAvailability(Object? value) =>
    switch (value) {
      'available' => CocoonApplicationAvailability.available,
      'unavailable' => CocoonApplicationAvailability.unavailable,
      _ => CocoonApplicationAvailability.unknown,
    };

CocoonApplicationEnrollmentState _applicationEnrollmentState(Object? value) =>
    switch (value) {
      'active' => CocoonApplicationEnrollmentState.active,
      'suspended' => CocoonApplicationEnrollmentState.suspended,
      'left' => CocoonApplicationEnrollmentState.left,
      'not_enrolled' => CocoonApplicationEnrollmentState.notEnrolled,
      _ => CocoonApplicationEnrollmentState.unknown,
    };

CocoonCommerceEligibilityState _commerceEligibilityState(Object? value) =>
    switch (value) {
      'entitled' => CocoonCommerceEligibilityState.entitled,
      'conversion_eligible' =>
        CocoonCommerceEligibilityState.conversionEligible,
      'offer_available' => CocoonCommerceEligibilityState.offerAvailable,
      'not_entitled' => CocoonCommerceEligibilityState.notEntitled,
      'unavailable' => CocoonCommerceEligibilityState.unavailable,
      'error' => CocoonCommerceEligibilityState.error,
      _ => CocoonCommerceEligibilityState.unknown,
    };

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : const <String, dynamic>{};

class CocoonGestationalAge {
  const CocoonGestationalAge({
    required this.totalDays,
    required this.week,
    required this.day,
    required this.basis,
  });

  factory CocoonGestationalAge.fromJson(Map<String, dynamic> json) =>
      CocoonGestationalAge(
        totalDays: (json['totalDays'] as num?)?.toInt(),
        week: (json['week'] as num?)?.toInt(),
        day: (json['day'] as num?)?.toInt(),
        basis: json['basis']?.toString(),
      );

  final int? totalDays;
  final int? week;
  final int? day;
  final String? basis;

  @override
  String toString() => 'CocoonGestationalAge(<redacted>)';
}

class CocoonPregnancyDating {
  const CocoonPregnancyDating({
    required this.method,
    required this.lmpDate,
    required this.estimatedDueDate,
    required this.referenceDate,
    required this.gestationalAgeAtReferenceDays,
    required this.gestationalAge,
  });

  factory CocoonPregnancyDating.fromJson(Map<String, dynamic> json) {
    final gestationalAgeJson = json['gestationalAge'];
    return CocoonPregnancyDating(
      method: json['method']?.toString(),
      lmpDate: json['lmpDate']?.toString(),
      estimatedDueDate: json['estimatedDueDate']?.toString(),
      referenceDate: json['referenceDate']?.toString(),
      gestationalAgeAtReferenceDays:
          (json['gestationalAgeAtReferenceDays'] as num?)?.toInt(),
      gestationalAge: gestationalAgeJson is Map<String, dynamic>
          ? CocoonGestationalAge.fromJson(gestationalAgeJson)
          : null,
    );
  }

  final String? method;
  final String? lmpDate;
  final String? estimatedDueDate;
  final String? referenceDate;
  final int? gestationalAgeAtReferenceDays;
  final CocoonGestationalAge? gestationalAge;

  @override
  String toString() => 'CocoonPregnancyDating(<redacted>)';
}

class CocoonPregnancyEpisode {
  const CocoonPregnancyEpisode({
    required this.id,
    required this.motherPersonId,
    required this.status,
    required this.dating,
    required this.outcome,
    required this.activatedAtUtc,
    required this.endedAtUtc,
    required this.version,
    required this.updatedAtUtc,
  });

  factory CocoonPregnancyEpisode.fromJson(Map<String, dynamic> json) =>
      CocoonPregnancyEpisode(
        id: json['id']?.toString() ?? '',
        motherPersonId: json['motherPersonId']?.toString() ?? '',
        status: _episodeStatus(json['status']),
        dating: CocoonPregnancyDating.fromJson(_object(json['dating'])),
        outcome: json['outcome']?.toString(),
        activatedAtUtc: DateTime.tryParse(
          json['activatedAtUtc']?.toString() ?? '',
        ),
        endedAtUtc: DateTime.tryParse(json['endedAtUtc']?.toString() ?? ''),
        version: (json['version'] as num?)?.toInt() ?? 0,
        updatedAtUtc: DateTime.tryParse(json['updatedAtUtc']?.toString() ?? ''),
      );

  final String id;
  final String motherPersonId;
  final CocoonPregnancyEpisodeStatus status;
  final CocoonPregnancyDating dating;
  final String? outcome;
  final DateTime? activatedAtUtc;
  final DateTime? endedAtUtc;
  final int version;
  final DateTime? updatedAtUtc;

  @override
  String toString() =>
      'CocoonPregnancyEpisode(id: <redacted>, status: ${status.name}, version: $version)';
}

class CocoonEntitlementSnapshot {
  const CocoonEntitlementSnapshot({
    required this.state,
    required this.reference,
    required this.currentPeriodEndUtc,
  });

  factory CocoonEntitlementSnapshot.fromJson(Map<String, dynamic> json) =>
      CocoonEntitlementSnapshot(
        state: _entitlementState(json['state']),
        reference: json['reference']?.toString(),
        currentPeriodEndUtc: DateTime.tryParse(
          json['currentPeriodEndUtc']?.toString() ?? '',
        ),
      );

  final CocoonEntitlementState state;
  final String? reference;
  final DateTime? currentPeriodEndUtc;
}

class CocoonApplicationStateSnapshot {
  const CocoonApplicationStateSnapshot({
    required this.availability,
    required this.enrollmentState,
  });

  factory CocoonApplicationStateSnapshot.fromJson(Map<String, dynamic> json) =>
      CocoonApplicationStateSnapshot(
        availability: _applicationAvailability(json['availability']),
        enrollmentState: _applicationEnrollmentState(json['enrollmentState']),
      );

  final CocoonApplicationAvailability availability;
  final CocoonApplicationEnrollmentState enrollmentState;
}

class CocoonCommerceEligibilitySnapshot {
  const CocoonCommerceEligibilitySnapshot({
    required this.state,
    required this.offerAvailable,
    required this.conversionEligible,
  });

  factory CocoonCommerceEligibilitySnapshot.fromJson(
    Map<String, dynamic> json,
  ) => CocoonCommerceEligibilitySnapshot(
    state: _commerceEligibilityState(json['state']),
    offerAvailable: json['offerAvailable'] == true,
    conversionEligible: json['conversionEligible'] == true,
  );

  final CocoonCommerceEligibilityState state;
  final bool offerAvailable;
  final bool conversionEligible;
}

class CocoonBootstrapSnapshot {
  const CocoonBootstrapSnapshot({
    required this.contractVersion,
    required this.personId,
    required this.enrollmentState,
    required this.entitlement,
    required this.application,
    required this.commerceEligibility,
    required this.activeEpisode,
    required this.serverAuthoritativeSharing,
    required this.serverAuthoritativeEntitlementActivation,
    required this.cachedOwnerSnapshotAllowed,
    required this.cachedSharedSnapshotAllowed,
  });

  factory CocoonBootstrapSnapshot.fromJson(Map<String, dynamic> json) {
    final runtime = _object(json['runtime']);
    final activeEpisode = json['activeEpisode'];
    return CocoonBootstrapSnapshot(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 1,
      personId: _object(json['subject'])['personId']?.toString() ?? '',
      enrollmentState: _enrollmentState(json['enrollmentState']),
      entitlement: CocoonEntitlementSnapshot.fromJson(
        _object(json['entitlementState']),
      ),
      application: CocoonApplicationStateSnapshot.fromJson(
        _object(json['applicationState']),
      ),
      commerceEligibility: CocoonCommerceEligibilitySnapshot.fromJson(
        _object(json['commerceEligibility']),
      ),
      activeEpisode: activeEpisode is Map<String, dynamic>
          ? CocoonPregnancyEpisode.fromJson(activeEpisode)
          : null,
      serverAuthoritativeSharing: runtime['serverAuthoritativeSharing'] == true,
      serverAuthoritativeEntitlementActivation:
          runtime['serverAuthoritativeEntitlementActivation'] == true,
      cachedOwnerSnapshotAllowed: runtime['cachedOwnerSnapshotAllowed'] == true,
      cachedSharedSnapshotAllowed:
          runtime['cachedSharedSnapshotAllowed'] == true,
    );
  }

  final int contractVersion;
  final String personId;
  final CocoonEnrollmentState enrollmentState;
  final CocoonEntitlementSnapshot entitlement;
  final CocoonApplicationStateSnapshot application;
  final CocoonCommerceEligibilitySnapshot commerceEligibility;
  final CocoonPregnancyEpisode? activeEpisode;
  final bool serverAuthoritativeSharing;
  final bool serverAuthoritativeEntitlementActivation;
  final bool cachedOwnerSnapshotAllowed;
  final bool cachedSharedSnapshotAllowed;

  @override
  String toString() =>
      'CocoonBootstrapSnapshot(contractVersion: $contractVersion, enrollmentState: ${enrollmentState.name}, applicationEnrollmentState: ${application.enrollmentState.name}, entitlementState: ${entitlement.state.name}, commerceEligibility: ${commerceEligibility.state.name})';
}

class CocoonPregnancySnapshot {
  const CocoonPregnancySnapshot({
    required this.contractVersion,
    required this.episode,
  });

  factory CocoonPregnancySnapshot.fromJson(Map<String, dynamic> json) {
    final episode = json['episode'];
    return CocoonPregnancySnapshot(
      contractVersion: (json['contractVersion'] as num?)?.toInt() ?? 1,
      episode: episode is Map<String, dynamic>
          ? CocoonPregnancyEpisode.fromJson(episode)
          : null,
    );
  }

  final int contractVersion;
  final CocoonPregnancyEpisode? episode;
}
