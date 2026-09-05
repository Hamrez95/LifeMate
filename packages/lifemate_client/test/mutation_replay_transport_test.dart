import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_client/src/mutation_replay_transport.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  LifeMateDurableMutation mutation({
    String method = 'POST',
    String endpointPath = '/api/v1/dose-occurrences/item/report?source=offline',
  }) => LifeMateDurableMutation(
    mutationId: 'request-1',
    domain: LifeMateMutationDomain.adherence,
    sourceKey: 'occurrence-1',
    method: method,
    endpointPath: endpointPath,
    payload: const <String, dynamic>{
      'clientRequestId': 'request-1',
      'status': 'taken',
    },
    createdAtUtc: DateTime.utc(2026, 9, 5, 3),
    timeZone: 'Asia/Tehran',
  );

  test('replays only to configured API origin with ephemeral auth', () async {
    final client = _RecordingClient(statusCode: 204);
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: Uri.parse('https://api.mylifemate.ir/gateway/'),
      accessToken: () => 'token-value',
      httpClient: client,
    );

    final response = await transport.send(mutation());

    expect(response.statusCode, 204);
    expect(client.requests, hasLength(1));
    final request = client.requests.single;
    expect(
      request.url.toString(),
      'https://api.mylifemate.ir/gateway/api/v1/dose-occurrences/item/report?source=offline',
    );
    expect(request.headers['authorization'], 'Bearer token-value');
    expect(request.headers['idempotency-key'], 'request-1');
    expect(request.headers['x-lifemate-replay'], '1');
    expect(jsonDecode(request.body), <String, dynamic>{
      'clientRequestId': 'request-1',
      'status': 'taken',
    });
    transport.close();
  });

  test('missing token maps to auth retry without network request', () async {
    final client = _RecordingClient(statusCode: 200);
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: Uri.parse('https://api.mylifemate.ir'),
      accessToken: () => null,
      httpClient: client,
    );

    final response = await transport.send(mutation());

    expect(response.statusCode, 401);
    expect(client.requests, isEmpty);
    transport.close();
  });

  test('transport failures use typed retry exception without leaking details', () async {
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: Uri.parse('https://api.mylifemate.ir'),
      accessToken: () => 'token',
      httpClient: _ThrowingClient(
        http.ClientException('sensitive provider detail'),
      ),
    );

    await expectLater(
      transport.send(mutation()),
      throwsA(isA<LifeMateMutationReplayTransportException>()),
    );
    transport.close();
  });

  test('timeout uses typed retry exception', () async {
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: Uri.parse('https://api.mylifemate.ir'),
      accessToken: () => 'token',
      httpClient: _NeverCompletesClient(),
      transportTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      transport.send(mutation()),
      throwsA(isA<LifeMateMutationReplayTransportException>()),
    );
    transport.close();
  });

  test('remote cleartext base URI is rejected before replay', () {
    expect(
      () => LifeMateHttpMutationReplayTransport(
        apiBaseUri: Uri.parse('http://api.example.test'),
        accessToken: () => 'token',
      ),
      throwsArgumentError,
    );
  });

  test('localhost cleartext remains available for development', () async {
    final client = _RecordingClient(statusCode: 200);
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: Uri.parse('http://localhost:8080'),
      accessToken: () => 'token',
      httpClient: client,
    );

    final response = await transport.send(mutation());

    expect(response.statusCode, 200);
    expect(client.requests.single.url.host, 'localhost');
    transport.close();
  });

  test('non-mutation HTTP methods fail visibly without network replay', () async {
    final client = _RecordingClient(statusCode: 200);
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: Uri.parse('https://api.mylifemate.ir'),
      accessToken: () => 'token',
      httpClient: client,
    );

    await expectLater(transport.send(mutation(method: 'GET')), throwsStateError);
    expect(client.requests, isEmpty);
    transport.close();
  });

  test('closing transport prevents later replay', () async {
    final transport = LifeMateHttpMutationReplayTransport(
      apiBaseUri: Uri.parse('https://api.mylifemate.ir'),
      accessToken: () => 'token',
      httpClient: _RecordingClient(statusCode: 200),
    );
    transport.close();

    await expectLater(transport.send(mutation()), throwsStateError);
  });
}

final class _RecordingClient extends http.BaseClient {
  _RecordingClient({required this.statusCode});

  final int statusCode;
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      throw StateError('Expected replay to use an http.Request.');
    }
    requests.add(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"ignored":"response"}')),
      statusCode,
    );
  }
}

final class _ThrowingClient extends http.BaseClient {
  _ThrowingClient(this.error);

  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw error;
  }
}

final class _NeverCompletesClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}
