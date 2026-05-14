import 'dart:convert';
import 'dart:io';
import 'default_db_data.dart';

class DatabaseService {
  static const String _fileName = 'db.json';

  // در بک‌اند، فایل مستقیماً در پوشه اصلی پروژه ایجاد می‌شود
  static File get _localFile {
    return File(_fileName);
  }

  Future<Map<String, dynamic>> readData() async {
    final file = _localFile;

    // اگر فایل وجود نداشت، داده‌های پیش‌فرض را می‌سازد
    if (!await file.exists()) {
      final defaultData = DefaultDbData.getDefaultData();
      await writeData(defaultData);
      return defaultData;
    }

    final content = await file.readAsString();
    return jsonDecode(content);
  }

  Future<void> writeData(Map<String, dynamic> data) async {
    final file = _localFile;
    await file.writeAsString(jsonEncode(data));
  }
}
