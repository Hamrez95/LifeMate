import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_core/lifemate_core.dart';

import 'durable_http_client.dart';
import 'lifemate_api_client.dart';
import 'offline_mutation_queue.dart';
import 'offline_sync_result.dart';
import 'shared_offline_runtime.dart';

class LifeMatePendingSyncEvent {
  const LifeMatePendingSyncEvent({
    required this.occurrenceId,
    required this.status,
  });

  final String occurrenceId;
  final String status;
}

final ValueNotifier<LifeMatePendingSyncEvent?> lifeMatePendingSyncEvent =
    ValueNotifier<LifeMatePendingSyncEvent?>(null);

/// Low-cardinality offline recovery feedback for UI notices. This intentionally
/// contains no account/person/occurrence IDs, health values or server messages.
final ValueNotifier<LifeMateOfflineSyncResult?> lifeMateOfflineSyncResult =
    ValueNotifier<LifeMateOfflineSyncResult?>(null);

class DurableLifeMateApiClient extends LifeMateApiClient {
  DurableLifeMateApiClient._({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    required LifeMateAccountIdProvider accountId,
    required LifeMateDurableHttpClient durableHttp,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _accountId = accountId,
        _durableHttp = durableHttp,
        super(
          baseUri: baseUri,
          accessToken: accessToken,
          httpClient: durableHttp,
        );

  factory DurableLifeMateApiClient({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    required LifeMateAccountIdProvider accountId,
    LifeMateOfflineMutationQueue? queue,
    http.Client? innerHttpClient,
  }) {
    final durableHttp = LifeMateDurableHttpClient(
      apiBaseUri: baseUri,
      accessToken: accessToken,
      accountId: accountId,
      queue: queue,
      inner: innerHttpClient,
    );
    return DurableLifeMateApiClient._(
      baseUri: baseUri,
      accessToken: accessToken,
      accountId: accountId,
      durableHttp: durableHttp,
    );
  }

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final LifeMateAccountIdProvider _accountId;
  final LifeMateDurableHttpClient _durableHttp;
  LifeMateSharedOfflineRuntime? _sharedRuntime;

  /// Moves replay ownership from the pre-#831 account-only queue to the shared
  /// encrypted Environment + Account + Person runtime. The caller must supply
  /// the canonical server-resolved self Person; Account is never substituted.
  Future<void> adoptSharedOfflineRuntime({
    required String environmentId,
    required String accountId,
    required String personId,
    required String timeZone,
  }) async {
    final normalizedAccount = accountId.trim();
    final normalizedPerson = personId.trim();
    final normalizedEnvironment = environmentId.trim();
    final normalizedTimeZone = timeZone.trim();
    if (normalizedAccount.isEmpty ||
        normalizedPerson.isEmpty ||
        normalizedEnvironment.isEmpty ||
        normalizedTimeZone.isEmpty) {
      throw ArgumentError(
        'Shared offline runtime requires environment, account, Person and timezone.',
      );
    }
    if (_accountId()?.trim() != normalizedAccount) {
      throw StateError('Authenticated account changed during offline adoption.');
    }

    final namespace = LifeMateLocalNamespace(
      environmentId: normalizedEnvironment,
      accountId: normalizedAccount,
      personId: normalizedPerson,
    );
    final current = _sharedRuntime;
    if (current != null && current.namespace == namespace) return;

    final next = await LifeMateSharedOfflineRuntime.open(
      namespace: namespace,
      timeZone: normalizedTimeZone,
      apiBaseUri: _baseUri,
      accessToken: _accessToken,
      legacyStorage: _durableHttp.migrationStorage,
    );
    if (_accountId()?.trim() != normalizedAccount) {
      next.close();
      throw StateError('Authenticated account changed during offline adoption.');
    }

    _sharedRuntime = next;
    _durableHttp.useReplayDelegate(next.flushDetailed);
    current?.close();
  }

  @override
  Future<Map<String, dynamic>> reportDose({
    required String occurrenceId,
    required String clientRequestId,
    required int version,
    required String status,
    required DateTime occurredAtUtc,
  }) async {
    try {
      return await super.reportDose(
        occurrenceId: occurrenceId,
        clientRequestId: clientRequestId,
        version: version,
        status: status,
        occurredAtUtc: occurredAtUtc,
      );
    } on LifeMateOfflineQueuedException {
      lifeMatePendingSyncEvent.value = LifeMatePendingSyncEvent(
        occurrenceId: occurrenceId,
        status: status,
      );
      return <String, dynamic>{
        'id': occurrenceId,
        'status': 'pending_sync',
        'pendingStatus': status,
        'version': version,
        'pendingSync': true,
        'clientRequestId': clientRequestId,
      };
    }
  }

  @override
  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final pendingBeforeRead = await _pendingDoseStates();
    final snapshot = await super.getHomeSnapshot(
      fromDate: fromDate,
      toDate: toDate,
    );
    if (pendingBeforeRead.isEmpty) return snapshot;

    final occurrences = snapshot['doseOccurrences'];
    if (occurrences is List) {
      snapshot['doseOccurrences'] = _overlayOccurrences(
        occurrences,
        pendingBeforeRead,
      );
    }
    return snapshot;
  }

  @override
  Future<List<Map<String, dynamic>>> getDoseOccurrences({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final pendingBeforeRead = await _pendingDoseStates();
    final values = await super.getDoseOccurrences(
      fromDate: fromDate,
      toDate: toDate,
    );
    if (pendingBeforeRead.isEmpty) return values;
    return _overlayOccurrences(values, pendingBeforeRead);
  }

  Future<Map<String, String>> _pendingDoseStates() async {
    final shared = _sharedRuntime;
    if (shared != null) return shared.pendingAdherenceStates();

    final pending = await _durableHttp.pendingMutations();
    final result = <String, String>{};
    for (final mutation in pending) {
      final uri = Uri.tryParse(mutation.uri);
      if (uri == null || uri.pathSegments.length < 2) continue;
      final reportIndex = uri.pathSegments.lastIndexOf('report');
      if (reportIndex <= 0) continue;
      final occurrenceId = uri.pathSegments[reportIndex - 1];
      dynamic body;
      try {
        body = jsonDecode(mutation.body);
      } catch (_) {
        continue;
      }
      if (body is! Map) continue;
      final status = body['status']?.toString().toLowerCase();
      if (status != 'taken' && status != 'skipped') continue;
      result[occurrenceId] = status!;
    }
    return result;
  }

  List<Map<String, dynamic>> _overlayOccurrences(
    List<dynamic> values,
    Map<String, String> pending,
  ) {
    return values.whereType<Map>().map((raw) {
      final value = <String, dynamic>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
      final id = value['id']?.toString();
      final desiredStatus = id == null ? null : pending[id];
      if (desiredStatus == null) return value;

      final serverStatus = value['status']?.toString().toLowerCase();
      if (serverStatus == 'taken' || serverStatus == 'skipped') return value;
      return <String, dynamic>{
        ...value,
        'status': 'pending_sync',
        'pendingSync': true,
        'pendingStatus': desiredStatus,
      };
    }).toList(growable: false);
  }

  Future<int> flushPendingMutations() async =>
      (await flushPendingMutationsDetailed()).synced;

  Future<LifeMateOfflineSyncResult> flushPendingMutationsDetailed() async {
    final result = await _durableHttp.flushPendingDetailed();
    lifeMateOfflineSyncResult.value = result;
    return result;
  }

  Future<int> pendingMutationCount() async {
    final shared = _sharedRuntime;
    return shared == null
        ? _durableHttp.pendingCount()
        : shared.pendingMutationCount();
  }

  @override
  void close() {
    _sharedRuntime?.close();
    _sharedRuntime = null;
    super.close();
  }
}
