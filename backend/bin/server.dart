import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

// In-memory shared state
final Map<String, dynamic> sharedState = {
  'currentIndex': 0,
  'scheduleList': [
    {'type': 'med', 'name': 'Acetaminophen'},
    {'type': 'med', 'name': 'Vitamin D'},
    {'type': 'med', 'name': 'Aspirin'},
    {'type': 'med', 'name': 'Metformin'},
    {'type': 'med', 'name': 'Atorvastatin'},
    {'type': 'med', 'name': 'Lisinopril'},
    {'type': 'med', 'name': 'Omeprazole'},
    {'type': 'med', 'name': 'Levothyroxine'},
    {'type': 'appt', 'name': 'Dr. Smith - Cardiology'},
    {'type': 'appt', 'name': 'Dr. Lee - Endocrinology'},
  ],
  'status': 'pending', // 'pending', 'taken', 'attended'
  'consumed': <int>[], // List of indices of consumed medications
};

Response _getStatus(Request request) {
  final idx = sharedState['currentIndex'] as int;
  final scheduleList = sharedState['scheduleList'] as List;
  final item = idx < scheduleList.length ? scheduleList[idx] : null;
  final consumed = sharedState['consumed'] as List<int>;
  // Next medications: all after currentIndex
  final nextMedications = idx + 1 < scheduleList.length
      ? scheduleList.sublist(idx + 1)
      : [];
  return Response.ok(jsonEncode({
    'currentIndex': idx,
    'item': item,
    'status': sharedState['status'],
    'scheduleList': scheduleList,
    'consumed': consumed,
    'nextMedications': nextMedications,
  }), headers: {'Content-Type': 'application/json'});
}

Future<Response> _postStatus(Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  if (data['currentIndex'] != null) {
    sharedState['currentIndex'] = data['currentIndex'];
  }
  if (data['status'] != null) {
    sharedState['status'] = data['status'];
    // If status is 'done', add to consumed
    if (data['status'] == 'done') {
      final idx = sharedState['currentIndex'] as int;
      final consumed = sharedState['consumed'] as List<int>;
      if (!consumed.contains(idx)) {
        consumed.add(idx);
      }
    }
  }
  return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
}

void main(List<String> args) async {
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler((Request request) async {
    if (request.method == 'GET' && request.url.path == 'status') {
      return _getStatus(request);
    }
    if (request.method == 'POST' && request.url.path == 'status') {
      return _postStatus(request);
    }
    return Response.notFound('Not Found');
  });

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Serving at http://${server.address.host}:${server.port}');
}
