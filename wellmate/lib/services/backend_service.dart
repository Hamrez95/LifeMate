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

  static Future<void> updateStatus({required int currentIndex, required String status}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'currentIndex': currentIndex, 'status': status}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to update status');
    }
  }
}
