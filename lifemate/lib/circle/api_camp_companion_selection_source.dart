import 'dart:collection';

import 'package:lifemate_client/lifemate_client.dart';

import 'camp_companion_selection.dart';

/// Production Circle -> Living Camp adapter.
///
/// Relationship membership and the normalized Circle access state are supplied
/// by the reviewed LifeMate API. This adapter never joins raw Supabase tables,
/// never interprets raw health values and never treats a relationship as proof
/// of protected-data authorization.
class ApiCampCompanionSelectionSource implements CampCompanionSelectionSource {
  ApiCampCompanionSelectionSource({
    required LifeMateApiClient apiClient,
    required bool isPersian,
    this.capacity = 2,
  }) : assert(capacity >= 0),
       _apiClient = apiClient,
       _isPersian = isPersian;

  final LifeMateApiClient _apiClient;
  final int capacity;
  bool _isPersian;
  final Set<String> _selectedPresentationIds = <String>{};

  void updateLocale({required bool isPersian}) {
    _isPersian = isPersian;
  }

  @override
  CampCompanionSourceMode get mode => CampCompanionSourceMode.live;

  @override
  Future<CampCompanionSelectionSnapshot> load() async {
    final rows = await _apiClient.getCareRelationships();
    final candidates = <CampCompanionCandidate>[];
    final eligibleIds = <String>{};

    for (final row in rows) {
      final candidate = _candidateFromApi(row);
      if (candidate == null) continue;
      candidates.add(candidate);
      if (candidate.isEligible) eligibleIds.add(candidate.presentationId);
    }

    // A revoke, account/person switch, or server-side eligibility change must
    // remove stale visual selections immediately. Cached presentation state is
    // never proof of current consent or authorization.
    _selectedPresentationIds.retainAll(eligibleIds);

    return CampCompanionSelectionSnapshot(
      candidates: List<CampCompanionCandidate>.unmodifiable(candidates),
      selectedPresentationIds: UnmodifiableSetView(
        Set<String>.from(_selectedPresentationIds),
      ),
      capacity: capacity,
    );
  }

  @override
  Future<void> setSelectedPresentationIds(Set<String> presentationIds) async {
    if (presentationIds.length > capacity) {
      throw StateError('Companion selection exceeds configured capacity.');
    }

    // Revalidate against canonical server state on every mutation so a stale UI
    // cannot select a revoked, switched-person, or foreign relationship.
    final snapshot = await load();
    final eligibleIds = snapshot.candidates
        .where((candidate) => candidate.isEligible)
        .map((candidate) => candidate.presentationId)
        .toSet();
    final denied = presentationIds.difference(eligibleIds);
    if (denied.isNotEmpty) {
      throw StateError('Companion selection contains an unavailable person.');
    }

    _selectedPresentationIds
      ..clear()
      ..addAll(presentationIds);
  }

  CampCompanionCandidate? _candidateFromApi(Map<String, dynamic> row) {
    final relationshipId = _text(row['id']);
    final viewerRole = _text(row['viewerRole']);
    final displayName = _text(row['counterpartDisplayName']);
    if (relationshipId == null ||
        displayName == null ||
        (viewerRole != 'patient' && viewerRole != 'caregiver')) {
      // Unknown viewer role is a fail-closed cross-user/person-switch case.
      return null;
    }

    final access = _access(row['circleAccessPresentation']);
    final serverEligible = row['campPresentationEligible'] == true;
    final eligible = access == _CircleAccess.connected && serverEligible;
    final relationship = LifeMateRelationshipPresentationPolicy.fromRaw(
      row['presentationType']?.toString() ?? row['relationshipType']?.toString(),
    );

    return CampCompanionCandidate(
      // Stable for presentation while avoiding raw database IDs in user copy.
      presentationId: 'care:$relationshipId',
      displayName: displayName,
      relationshipLabel: relationship.relationshipLabel(isPersian: _isPersian),
      isEligible: eligible,
      ineligibleReason: eligible ? null : _accessLabel(access),
    );
  }

  _CircleAccess _access(Object? value) => switch (_text(value)) {
    'connected' => _CircleAccess.connected,
    'permission_required' => _CircleAccess.permissionRequired,
    _ => _CircleAccess.unavailable,
  };

  String _accessLabel(_CircleAccess access) => switch (access) {
    _CircleAccess.connected => _isPersian ? 'متصل' : 'Connected',
    _CircleAccess.permissionRequired =>
      _isPersian ? 'نیاز به اجازه' : 'Permission required',
    _CircleAccess.unavailable =>
      _isPersian ? 'دسترسی در دسترس نیست' : 'Access unavailable',
  };

  static String? _text(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}

enum _CircleAccess { connected, permissionRequired, unavailable }
