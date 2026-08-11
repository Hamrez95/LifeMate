import 'package:http/http.dart' as http;

import 'durable_http_client.dart';
import 'lifemate_api_client.dart';
import 'offline_mutation_queue.dart';

/// Production API client used by authenticated LifeMate app surfaces.
/// Reads and ordinary mutations behave exactly like [LifeMateApiClient]. Only
/// explicitly-idempotent medication adherence writes are journaled for replay.
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

  /// A persisted offline adherence action is an accepted local action, not a
  /// failed tap. Returning a pending-sync projection lets every existing dose
  /// surface (including the primary home card) become non-repeatable locally
  /// without each screen having to understand transport internals.
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
      return <String, dynamic>{
        'id': occurrenceId,
        'status': status,
        'version': version + 1,
        'pendingSync': true,
        'clientRequestId': clientRequestId,
      };
    }
  }

  Future<int> flushPendingMutations() => _durableHttp.flushPending();

  Future<int> pendingMutationCount() => _durableHttp.pendingCount();
}
