import 'shared_offline_runtime_web.dart' show LifeMateSharedOfflineRuntime;

final class CocoonPregnancyOfflineContentRecord {
  const CocoonPregnancyOfflineContentRecord({
    required this.recordKey,
    required this.payload,
    required this.contentVersion,
    required this.ruleVersion,
    required this.storedAtUtc,
  });

  final String recordKey;
  final Map<String, dynamic> payload;
  final String contentVersion;
  final String? ruleVersion;
  final DateTime storedAtUtc;
}

final class CocoonPregnancyOfflineContentCache {
  CocoonPregnancyOfflineContentCache._();

  static Future<CocoonPregnancyOfflineContentCache> open({
    required LifeMateSharedOfflineRuntime runtime,
    Object? store,
    DateTime Function()? now,
  }) => Future<CocoonPregnancyOfflineContentCache>.error(_unsupported());

  Future<void> writeApprovedContent({
    required String recordKey,
    required Map<String, dynamic> payload,
    required String contentVersion,
    String? ruleVersion,
  }) => Future<void>.error(_unsupported());

  Future<CocoonPregnancyOfflineContentRecord?> readApprovedContent({
    required String recordKey,
  }) => Future<CocoonPregnancyOfflineContentRecord?>.error(_unsupported());

  Future<void> deleteApprovedContent({required String recordKey}) =>
      Future<void>.error(_unsupported());

  void close() {}

  static UnsupportedError _unsupported() => UnsupportedError(
    'Protected offline health execution is unavailable on web.',
  );
}
