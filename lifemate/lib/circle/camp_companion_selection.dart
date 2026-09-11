import 'dart:collection';

import 'package:flutter/foundation.dart';

enum CampCompanionSourceMode { live, synthetic, unavailable }

@immutable
class CampCompanionCandidate {
  const CampCompanionCandidate({
    required this.presentationId,
    required this.displayName,
    required this.relationshipLabel,
    required this.isEligible,
    this.ineligibleReason,
  });

  final String presentationId;
  final String displayName;
  final String relationshipLabel;
  final bool isEligible;

  /// Presentation-safe explanation supplied by a reviewed adapter. It must not
  /// expose consent, authorization, or sensitive-health internals.
  final String? ineligibleReason;
}

@immutable
class CampCompanionSelectionSnapshot {
  const CampCompanionSelectionSnapshot({
    required this.candidates,
    required this.selectedPresentationIds,
    required this.capacity,
  });

  final List<CampCompanionCandidate> candidates;
  final Set<String> selectedPresentationIds;
  final int capacity;
}

abstract interface class CampCompanionSelectionSource {
  CampCompanionSourceMode get mode;

  Future<CampCompanionSelectionSnapshot> load();

  /// Persists presentation selection only. This method must never create or
  /// change a relationship, consent, authorization, or entitlement.
  Future<void> setSelectedPresentationIds(Set<String> presentationIds);
}

class CampCompanionSelectionUnavailable implements Exception {
  const CampCompanionSelectionUnavailable();
}

class UnavailableCampCompanionSelectionSource
    implements CampCompanionSelectionSource {
  const UnavailableCampCompanionSelectionSource();

  @override
  CampCompanionSourceMode get mode => CampCompanionSourceMode.unavailable;

  @override
  Future<CampCompanionSelectionSnapshot> load() async =>
      throw const CampCompanionSelectionUnavailable();

  @override
  Future<void> setSelectedPresentationIds(Set<String> presentationIds) async =>
      throw const CampCompanionSelectionUnavailable();
}

/// Explicit preview/test implementation. It is not canonical relationship,
/// consent, authorization, or production Camp state.
class SyntheticCampCompanionSelectionSource
    implements CampCompanionSelectionSource {
  SyntheticCampCompanionSelectionSource({
    required Iterable<CampCompanionCandidate> candidates,
    Iterable<String> selectedPresentationIds = const <String>[],
    this.capacity = 2,
  }) : assert(capacity >= 0),
       _candidates = List<CampCompanionCandidate>.unmodifiable(candidates),
       _selected = <String>{...selectedPresentationIds};

  final List<CampCompanionCandidate> _candidates;
  final int capacity;
  Set<String> _selected;

  @override
  CampCompanionSourceMode get mode => CampCompanionSourceMode.synthetic;

  @override
  Future<CampCompanionSelectionSnapshot> load() async {
    final eligibleIds = _candidates
        .where((candidate) => candidate.isEligible)
        .map((candidate) => candidate.presentationId)
        .toSet();
    final safeSelected = _selected.intersection(eligibleIds);
    return CampCompanionSelectionSnapshot(
      candidates: UnmodifiableListView(_candidates),
      selectedPresentationIds: UnmodifiableSetView(safeSelected),
      capacity: capacity,
    );
  }

  @override
  Future<void> setSelectedPresentationIds(Set<String> presentationIds) async {
    final eligibleIds = _candidates
        .where((candidate) => candidate.isEligible)
        .map((candidate) => candidate.presentationId)
        .toSet();
    final safeSelection = presentationIds.intersection(eligibleIds);
    if (safeSelection.length > capacity) {
      throw StateError('Companion selection exceeds configured capacity.');
    }
    _selected = safeSelection;
  }
}
