import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'durable_http_client.dart';
import 'lifemate_api_client.dart';
import 'offline_mutation_queue.dart';

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

class DurableLifeMateApiClient extends LifeMateApiClient {
  DurableLifeMateApiClient._({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    required LifeMateDurableHttpClient durableHttp,
  })  : _durableHttp = durableHttp,
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
      durableHttp: durableHttp,
    );
  }

  final LifeMateDurableHttpClient _durableHttp;

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
        'version': version + 1,
        'pendingSync': true,
        'clientRequestId': clientRequestId,
      };
    }
  }

  /// Snapshot pending entries *before* the GET begins. If replay succeeds while
  /// the GET is in flight, that GET may still return the older scheduled row.
  /// Retaining the pre-read snapshot keeps that response non-actionable; the
  /// following refresh can then observe the confirmed server state.
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
      snapshot['doseOccurrences'] =
          _overlayOccurrences(occurrences, pendingBeforeRead);
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

  Future<int> flushPendingMutations() => _durableHttp.flushPending();

  Future<int> pendingMutationCount() => _durableHttp.pendingCount();
}
