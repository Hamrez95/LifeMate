import 'dart:convert';
import 'package:http/http.dart' as http;

class BackendService {
  static const String baseUrl = 'http://localhost:8080';

  static Future<Map<String, dynamic>> getStatus() async {
    final res = await http.get(Uri.parse('$baseUrl/status'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception('Failed to fetch status');
  }

  // پارامترهای currentIndex و itemId اختیاری (nullable) شدند
  static Future<void> updateStatus({
    int? currentIndex,
    required String status,
    int? itemId, // 👈 این پارامتر اضافه شد
  }) async {
    // ساخت داینامیک بادی درخواست
    final Map<String, dynamic> requestBody = {'status': status};
    if (currentIndex != null) requestBody['currentIndex'] = currentIndex;
    if (itemId != null) requestBody['itemId'] = itemId;

    final res = await http.post(
      Uri.parse('$baseUrl/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to update status');
    }
  }
}
