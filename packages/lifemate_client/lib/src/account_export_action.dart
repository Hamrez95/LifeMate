import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

/// Owns the temporary beta clipboard transport used by account export.
///
/// Only a SHA-256 digest of the exported text is persisted. The export itself is
/// never stored by LifeMate. This lets a later app launch/resume clear the
/// clipboard only when it still contains the exact LifeMate export; unrelated
/// clipboard content is never erased.
class LifeMateSensitiveClipboardGuard with WidgetsBindingObserver {
  LifeMateSensitiveClipboardGuard._();

  static const _digestKey = 'lifemate_sensitive_export_clipboard_sha256_v1';
  static const _cleanupDelay = Duration(minutes: 1);
  static final LifeMateSensitiveClipboardGuard _instance =
      LifeMateSensitiveClipboardGuard._();
  static bool _installed = false;
  static Timer? _timer;

  static Future<void> install() async {
    if (!_installed) {
      WidgetsBinding.instance.addObserver(_instance);
      _installed = true;
    }
    await cleanupPendingExport();
  }

  static Future<void> copyExport(String text) async {
    await install();
    await Clipboard.setData(ClipboardData(text: text));
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_digestKey, _digest(text));
    _timer?.cancel();
    _timer = Timer(_cleanupDelay, () {
      unawaited(cleanupPendingExport());
    });
  }

  static Future<void> cleanupPendingExport() async {
    final prefs = SharedPreferencesAsync();
    final expectedDigest = await prefs.getString(_digestKey);
    if (expectedDigest == null || expectedDigest.isEmpty) return;

    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      final currentText = current?.text;
      if (currentText == null || currentText.isEmpty) {
        await prefs.remove(_digestKey);
        return;
      }

      if (_digest(currentText) == expectedDigest) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      // A digest mismatch means the user has replaced the clipboard. In both
      // cases this LifeMate export no longer owns the clipboard slot.
      await prefs.remove(_digestKey);
    } catch (_) {
      // Some platforms temporarily deny clipboard reads in background states.
      // Keep the digest so the next resume/launch can retry safely.
    }
  }

  static String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(cleanupPendingExport());
    }
  }
}

/// Self-service beta export. Data is fetched only after an explicit user action.
/// Clipboard delivery requires a second confirmation and is guarded across app
/// lifecycle/relaunch without persisting the exported JSON itself.
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
        'یک نسخه JSON از اطلاعات حساب، درمان‌ها، ثبت‌های سلامت، داده‌های بانوان و رضایت‌های خودت آماده می‌شود. رمزها، توکن‌ها و اطلاعات خصوصی طرف مقابل وارد فایل نمی‌شوند.',
        style: TextStyle(fontFamily: fontFamily, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('آماده‌سازی'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final api = LifeMateAccountExportApi.fromEnvironment();
  Map<String, dynamic> exported;
  try {
    exported = await api.exportMyData();
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
  final copy = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        'نسخه داده‌ها آماده است',
        style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w900),
      ),
      content: Text(
        'نسخه در همین لحظه آماده شد${generatedAt.isEmpty ? '' : ' ($generatedAt)'}.\n\nدر نسخه بتا می‌توانی JSON را موقتاً در کلیپ‌بورد کپی کنی. اگر هنوز همان داده باشد، LifeMate بعد از یک دقیقه یا در بازگشت بعدی به برنامه آن را پاک می‌کند؛ داده اصلی روی دستگاه ذخیره نمی‌شود.',
        style: TextStyle(fontFamily: fontFamily, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('بستن'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('کپی موقت JSON'),
        ),
      ],
    ),
  );
  if (copy != true || !context.mounted) return;

  await LifeMateSensitiveClipboardGuard.copyExport(jsonText);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('JSON موقتاً کپی شد و LifeMate پاک‌سازی امن آن را پیگیری می‌کند.'),
      ),
    );
  }
}
