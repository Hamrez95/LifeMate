import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'lifemate_api_client.dart';

class LifeMateAccountExportApi {
  LifeMateAccountExportApi({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
  })  : _baseUri = baseUri,
        _accessToken = accessToken,
        _http = httpClient ?? http.Client();

  factory LifeMateAccountExportApi.fromEnvironment({http.Client? httpClient}) {
    final config = AppConfig.fromEnvironment();
    return LifeMateAccountExportApi(
      baseUri: config.apiBaseUri,
      accessToken: () =>
          Supabase.instance.client.auth.currentSession?.accessToken,
      httpClient: httpClient,
    );
  }

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final http.Client _http;
  static const _timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> exportMyData() async {
    final token = _accessToken()?.trim();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    late final http.Response response;
    try {
      response = await _http.get(
        Uri.parse('$base/api/v1/account/export'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeout);
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'LifeMate request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'LifeMate service is unavailable.',
      );
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('LifeMate export response is invalid.');
    }
    final problem = decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    throw LifeMateApiException(
      statusCode: response.statusCode,
      code: (problem['code'] ?? problem['title'] ?? 'request_failed').toString(),
      message: (problem['detail'] ?? 'LifeMate export failed.').toString(),
    );
  }

  void close() => _http.close();
}

/// Self-service beta export. The export is fetched only after an explicit user
/// action and is handed to the operating-system share sheet as an in-memory JSON
/// file. LifeMate does not place the health export on the general clipboard and
/// does not persist the JSON in its own application storage.
Future<void> showLifeMateAccountExportDialog(
  BuildContext context, {
  required String fontFamily,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        'دریافت داده‌های من',
        style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w900),
      ),
      content: Text(
        'یک نسخه JSON از اطلاعات حساب، درمان‌ها، ثبت‌های سلامت، داده‌های بانوان و رضایت‌های خودت آماده می‌شود. رمزها، توکن‌ها و اطلاعات خصوصی طرف مقابل وارد فایل نمی‌شوند. بعد از آماده‌سازی، خودت مقصد فایل را از پنجره اشتراک گوشی انتخاب می‌کنی.',
        style: TextStyle(fontFamily: fontFamily, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('آماده‌سازی و اشتراک'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final api = LifeMateAccountExportApi.fromEnvironment();
  Map<String, dynamic> exported;
  try {
    exported = await api.exportMyData();
  } on LifeMateApiException catch (error) {
    if (!context.mounted) return;
    final message = error.statusCode == 429
        ? 'برای حفاظت از داده‌ها، حداکثر سه خروجی در ۲۴ ساعت مجاز است.'
        : 'دریافت داده‌ها انجام نشد. اتصال را بررسی کن.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    return;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('دریافت داده‌ها انجام نشد. اتصال را بررسی کن.'),
        ),
      );
    }
    return;
  } finally {
    api.close();
  }
  if (!context.mounted) return;

  final jsonText = const JsonEncoder.withIndent('  ').convert(exported);
  final generatedAt = exported['generatedAtUtc']?.toString() ?? '';
  final stamp = DateTime.tryParse(generatedAt)?.toUtc() ?? DateTime.now().toUtc();
  final fileName =
      'lifemate-data-${stamp.year.toString().padLeft(4, '0')}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}.json';
  final box = context.findRenderObject() as RenderBox?;

  try {
    await SharePlus.instance.share(
      ShareParams(
        title: 'خروجی داده‌های LifeMate',
        subject: 'LifeMate data export',
        files: [
          XFile.fromData(
            utf8.encode(jsonText),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: [fileName],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
        downloadFallbackEnabled: false,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('پنجره اشتراک باز نشد؛ دوباره تلاش کن.'),
      ),
    );
  }
}
