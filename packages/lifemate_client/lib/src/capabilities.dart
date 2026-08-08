class LifeMateCapabilitySnapshot {
  const LifeMateCapabilitySnapshot({
    required this.accountId,
    required this.selfPersonId,
    required this.applications,
    required this.features,
  });

  final String accountId;
  final String? selfPersonId;
  final Set<String> applications;
  final Set<String> features;

  bool hasFeature(String code) => features.contains(code);
  bool enrolledIn(String applicationCode) =>
      applications.contains(applicationCode);

  factory LifeMateCapabilitySnapshot.fromJson(Map<String, dynamic> json) {
    final accountId = json['accountId']?.toString() ?? '';
    if (accountId.isEmpty) {
      throw const FormatException('Capability snapshot is missing accountId.');
    }
    return LifeMateCapabilitySnapshot(
      accountId: accountId,
      selfPersonId: _nullableString(json['selfPersonId']),
      applications: _stringSet(json['applications']),
      features: _stringSet(json['features']),
    );
  }
}

class LifeMateAccountDeletionStatus {
  const LifeMateAccountDeletionStatus({
    required this.id,
    required this.status,
    required this.requestedAtUtc,
    required this.processingStartedAtUtc,
    required this.completedAtUtc,
    required this.retentionPolicyVersion,
  });

  final String id;
  final String status;
  final DateTime? requestedAtUtc;
  final DateTime? processingStartedAtUtc;
  final DateTime? completedAtUtc;
  final String? retentionPolicyVersion;

  bool get isTerminal => status == 'completed' || status == 'failed';

  factory LifeMateAccountDeletionStatus.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final status = json['status']?.toString().toLowerCase() ?? '';
    if (id.isEmpty || status.isEmpty) {
      throw const FormatException('Account deletion status is incomplete.');
    }
    return LifeMateAccountDeletionStatus(
      id: id,
      status: status,
      requestedAtUtc: _dateTime(json['requestedAtUtc']),
      processingStartedAtUtc: _dateTime(json['processingStartedAtUtc']),
      completedAtUtc: _dateTime(json['completedAtUtc']),
      retentionPolicyVersion: _nullableString(json['retentionPolicyVersion']),
    );
  }
}

Set<String> _stringSet(dynamic value) {
  if (value is! List) return const <String>{};
  return value
      .whereType<Object>()
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toSet();
}

String? _nullableString(dynamic value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

DateTime? _dateTime(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}
