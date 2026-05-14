import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../services/database_service.dart';

class StatusHandler {
  final DatabaseService _dbService = DatabaseService();

  Router get router {
    final router = Router();
    router.get('/status', _getStatus);
    router.post('/status', _postStatus);
    return router;
  }

  Future<Response> _getStatus(Request request) async {
    final data = await _dbService.readData();

    final idx = data['currentIndex'] as int;
    final scheduleList = data['scheduleList'] as List;
    final item = idx < scheduleList.length ? scheduleList[idx] : null;
    final nextItems =
        idx + 1 < scheduleList.length ? scheduleList.sublist(idx + 1) : [];

    final responseData = {
      'currentIndex': idx,
      'currentItem': item,
      'status': data['status'],
      'scheduleList': scheduleList,
      'consumedIndices': data['consumed'],
      'nextItems': nextItems,
    };

    return Response.ok(
      jsonEncode(responseData),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _postStatus(Request request) async {
    final body = await request.readAsString();
    final requestData = jsonDecode(body);

    final dbData = await _dbService.readData();

    if (requestData['currentIndex'] != null) {
      dbData['currentIndex'] = requestData['currentIndex'];
    }

    // 👈 منطق ثبت داروی مصرف شده اصلاح شد
    if (requestData['status'] == 'done' && requestData['itemId'] != null) {
      dbData['status'] = requestData['status'];

      // گرفتن آیدی ارسال شده از سمت فلاتر
      final itemId = requestData['itemId'] as int;
      List<dynamic> consumed = dbData['consumed'] ?? [];

      // اگر این آیدی قبلا ثبت نشده، به لیست اضافه بشه
      if (!consumed.contains(itemId)) {
        consumed.add(itemId);
      }
      dbData['consumed'] = consumed;
    }

    await _dbService.writeData(dbData);

    return Response.ok(
      jsonEncode({'ok': true}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}
