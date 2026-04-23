import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import '../lib/handlers/status_handler.dart';

void main(List<String> args) async {
  // ساخت نمونه از هندلر مسیرها
  final statusHandler = StatusHandler();

  // تنظیمات پایپ‌لاین (Middleware ها و Router)
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(statusHandler.router.call);

  // راه‌اندازی سرور
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);

  print('✅ Server is running at http://${server.address.host}:${server.port}');
  print('📂 Data will be saved locally in db.json');
}
