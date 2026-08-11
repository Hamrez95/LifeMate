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
/// action and is handed to the operating-system share sheet as text. LifeMate
/// never places the health export on the general clipboard and does not create a
/// temporary attachment/cache file or persist the JSON in application storage.
/// If the platform share operation fails, the same in-memory payload can be
/// retried without consuming another server-side export quota slot.
Future<void> showLifeMateAccountExportDialog(
  BuildContext context, {
  required String fontFamily,
}) async {
  final isPersian = Localizations.localeOf(context).languageCode == 'fa';
  String t(String fa, String en) => isPersian ? fa : en;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        t('دریافت داده‌های من', 'Export my data'),
        style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w900),
      ),
      content: Text(
        t(
          'یک نسخه JSON از اطلاعات حساب، درمان‌ها، ثبت‌های سلامت، داده‌های بانوان و رضایت‌های خودت آماده می‌شود. رمزها، توکن‌ها و اطلاعات خصوصی طرف مقابل وارد خروجی نمی‌شوند. بعد از آماده‌سازی، خودت مقصد را از پنجره اشتراک گوشی انتخاب می‌کنی.',
          'LifeMate will prepare a JSON copy of your account, treatments, health records, women-health data and your own consent records. Passwords, tokens and the other person’s private data are excluded. After preparation, you choose the destination from your device share sheet.',
        ),
        style: TextStyle(fontFamily: fontFamily, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(t('انصراف', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(t('آماده‌سازی و اشتراک', 'Prepare and share')),
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
        ? t(
            'برای حفاظت از داده‌ها، حداکثر سه خروجی در ۲۴ ساعت مجاز است.',
            'To protect your data, at most three exports are allowed in 24 hours.',
          )
        : t(
            'دریافت داده‌ها انجام نشد. اتصال را بررسی کن.',
            'Could not export your data. Check your connection and try again.',
          );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    return;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'دریافت داده‌ها انجام نشد. اتصال را بررسی کن.',
              'Could not export your data. Check your connection and try again.',
            ),
          ),
        ),
      );
    }
    return;
  } finally {
    api.close();
  }
  if (!context.mounted) return;

  // Keep one server response in memory for all share retries. A share-sheet
  // failure must not cause a second API request or burn another quota slot.
  final jsonText = const JsonEncoder.withIndent('  ').convert(exported);
  final box = context.findRenderObject() as RenderBox?;

  while (context.mounted) {
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: t('خروجی داده‌های LifeMate', 'LifeMate data export'),
          subject: 'LifeMate data export',
          text: jsonText,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
          downloadFallbackEnabled: false,
        ),
      );
      return;
    } catch (_) {
      if (!context.mounted) return;
      final retry = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            t('اشتراک انجام نشد', 'Sharing failed'),
            style: TextStyle(
              fontFamily: fontFamily,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            t(
              'خروجی هنوز فقط در حافظه همین صفحه است. می‌توانی بدون درخواست دوباره از سرور، اشتراک را دوباره امتحان کنی.',
              'The export is still only in this screen’s memory. You can retry sharing without requesting another export from the server.',
            ),
            style: TextStyle(fontFamily: fontFamily, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('بستن', 'Close')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('تلاش دوباره', 'Retry')),
            ),
          ],
        ),
      );
      if (retry != true) return;
    }
  }
}
