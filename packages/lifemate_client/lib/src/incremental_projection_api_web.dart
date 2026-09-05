import 'package:http/http.dart' as http;

import 'lifemate_api_client.dart';

/// Browser builds may still use the normal online LifeMate API, but durable
/// health projection transport is native-only until a separately reviewed
/// protected browser store exists.
final class LifeMateIncrementalProjectionApi {
  LifeMateIncrementalProjectionApi({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
  });

  Future<Object> pullCareEvents({String? cursor, int limit = 100}) =>
      Future<Object>.error(
        UnsupportedError(
          'Protected offline health execution is unavailable on web.',
        ),
      );

  void close() {}
}
