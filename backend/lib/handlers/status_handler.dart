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

    // خواندن دیتابیس فعلی
    final dbData = await _dbService.readData();

    if (requestData['currentIndex'] != null) {
      dbData['currentIndex'] = requestData['currentIndex'];
    }

    if (requestData['status'] != null) {
      dbData['status'] = requestData['status'];

      if (requestData['status'] == 'done') {
        final idx = dbData['currentIndex'] as int;
        List<dynamic> consumed = dbData['consumed'];
        if (!consumed.contains(idx)) {
          consumed.add(idx);
        }
      }
    }

    // ذخیره تغییرات در فایل JSON
    await _dbService.writeData(dbData);

    return Response.ok(
      jsonEncode({'ok': true}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }
}
