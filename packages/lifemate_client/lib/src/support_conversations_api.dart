import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

class LifeMateSupportConversation {
  const LifeMateSupportConversation({
    required this.id,
    required this.status,
    required this.productCode,
    required this.lastActivityAtUtc,
  });

  factory LifeMateSupportConversation.fromJson(Map<String, dynamic> json) {
    final id = json['ticketId']?.toString() ?? '';
    final status = json['status']?.toString() ?? '';
    final activityRaw = json['lastActivityAtUtc']?.toString();
    if (id.isEmpty || status.isEmpty || activityRaw == null) {
      throw const FormatException('support_conversation_invalid');
    }
    return LifeMateSupportConversation(
      id: id,
      status: status,
      productCode: json['productCode']?.toString(),
      lastActivityAtUtc: DateTime.parse(activityRaw),
    );
  }

  final String id;
  final String status;
  final String? productCode;
  final DateTime lastActivityAtUtc;
}

class LifeMateSupportMessage {
  const LifeMateSupportMessage({
    required this.id,
    required this.body,
    required this.createdAtUtc,
    required this.fromUser,
  });

  factory LifeMateSupportMessage.fromJson(Map<String, dynamic> json) {
    final messageId = json['messageId']?.toString() ?? json['id']?.toString() ?? '';
    final senderKind = json['senderKind']?.toString() ?? json['senderType']?.toString() ?? '';
    final body = json['body']?.toString() ?? '';
    final createdAtRaw = json['createdAtUtc']?.toString();
    if (messageId.isEmpty || body.isEmpty || createdAtRaw == null) {
      throw const FormatException('support_message_invalid');
    }
    return LifeMateSupportMessage(
      id: messageId,
      body: body,
      createdAtUtc: DateTime.parse(createdAtRaw),
      fromUser: senderKind == 'User',
    );
  }

  final String id;
  final String body;
  final DateTime createdAtUtc;
  final bool fromUser;
}

typedef LifeMateSupportTokenProvider = String? Function();

class LifeMateSupportApi {
  LifeMateSupportApi({
    required this.baseUri,
    required Future<String> Function() accessToken,
    http.Client? client,
  })  : _asyncAccessToken = accessToken,
        _accessToken = null,
        _client = client ?? http.Client();

  LifeMateSupportApi._sync({
    required this.baseUri,
    required LifeMateSupportTokenProvider accessToken,
    http.Client? client,
  })  : _accessToken = accessToken,
        _asyncAccessToken = null,
        _client = client ?? http.Client();

  factory LifeMateSupportApi.fromEnvironment({http.Client? client}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateSupportApi._sync(
      baseUri: config.apiBaseUri,
      accessToken: () => Supabase.instance.client.auth.currentSession?.accessToken,
      client: client,
    );
  }

  final Uri baseUri;
  final Future<String> Function()? _asyncAccessToken;
  final LifeMateSupportTokenProvider? _accessToken;
  final http.Client _client;

  Future<String> _token() async {
    final token = _asyncAccessToken != null ? await _asyncAccessToken!() : _accessToken?.call();
    if (token == null || token.isEmpty) {
      throw const LifeMateSupportException(401, 'session_missing');
    }
    return token;
  }

  Future<Map<String, String>> _headers() async => {
        'authorization': 'Bearer ${await _token()}',
        'content-type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
        path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
        queryParameters: query,
      );

  Future<LifeMateSupportConversation?> current({String? productCode}) async {
    final data = _json(
      await _client.get(
        _uri('/api/v1/support/conversations/current', {
          if (productCode != null && productCode.isNotEmpty) 'productCode': productCode,
        }),
        headers: await _headers(),
      ),
    );
    final value = data['conversation'];
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('support_conversation_invalid');
    }
    return LifeMateSupportConversation.fromJson(Map<String, dynamic>.from(value));
  }

  Future<Map<String, dynamic>> open({
    String? productCode,
    String category = 'general',
    required String body,
    required String clientMessageId,
  }) async {
    final existing = await current(productCode: productCode);
    if (existing != null) {
      return send(
        existing.id,
        body: body,
        clientMessageId: clientMessageId,
      );
    }
    return _json(
      await _client.post(
        _uri('/api/v1/support/conversations'),
        headers: await _headers(),
        body: jsonEncode({
          'productCode': productCode,
          'category': category,
          'body': body,
          'clientMessageId': clientMessageId,
        }),
      ),
    );
  }

  Future<List<LifeMateSupportMessage>> messages(
    String conversationId, {
    String? afterAt,
    int limit = 50,
  }) async {
    final data = _json(
      await _client.get(
        _uri('/api/v1/support/conversations/$conversationId', {
          'limit': '$limit',
          if (afterAt != null) 'afterAt': afterAt,
        }),
        headers: await _headers(),
      ),
    );
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (entry) => LifeMateSupportMessage.fromJson(
            Map<String, dynamic>.from(entry),
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> send(
    String conversationId, {
    required String body,
    required String clientMessageId,
  }) async =>
      _json(
        await _client.post(
          _uri('/api/v1/support/conversations/$conversationId/messages'),
          headers: await _headers(),
          body: jsonEncode({
            'body': body,
            'clientMessageId': clientMessageId,
          }),
        ),
      );

  Future<void> markRead(String conversationId, String messageId) async {
    _json(
      await _client.post(
        _uri('/api/v1/support/conversations/$conversationId/read'),
        headers: await _headers(),
        body: jsonEncode({'messageId': messageId}),
      ),
    );
  }

  Future<Map<String, dynamic>> upload(
    String conversationId,
    String messageId, {
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final headers = await _headers();
    headers['content-type'] = contentType;
    headers['x-file-name'] = fileName;
    final request = http.Request(
      'PUT',
      _uri(
        '/api/v1/support/conversations/$conversationId/messages/$messageId/attachments',
      ),
    )
      ..headers.addAll(headers)
      ..bodyBytes = bytes;
    return _json(await http.Response.fromStream(await _client.send(request)));
  }

  Future<Uri> attachmentDownload(
    String conversationId,
    String attachmentId,
  ) async {
    final data = _json(
      await _client.get(
        _uri(
          '/api/v1/support/conversations/$conversationId/attachments/$attachmentId/download',
        ),
        headers: await _headers(),
      ),
    );
    final signedUrl = data['signedUrl']?.toString();
    if (signedUrl == null || signedUrl.isEmpty) {
      throw const FormatException('support_attachment_download_invalid');
    }
    return Uri.parse(signedUrl);
  }

  Map<String, dynamic> _json(http.Response response) {
    Map<String, dynamic> body = {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LifeMateSupportException(
        response.statusCode,
        body['code']?.toString() ?? 'support_request_failed',
      );
    }
    return body;
  }

  void close() => _client.close();
}

class LifeMateSupportException implements Exception {
  const LifeMateSupportException(this.statusCode, this.code);

  final int statusCode;
  final String code;
}
