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

  Future<int> flushPendingMutations() => _durableHttp.flushPending();

  Future<int> pendingMutationCount() => _durableHttp.pendingCount();
}
