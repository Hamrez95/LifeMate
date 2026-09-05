from pathlib import Path

path = Path('packages/lifemate_client/lib/src/durable_lifemate_api_client.dart')
text = path.read_text()

anchor = """  @override\n  Future<List<Map<String, dynamic>>> getDoseOccurrences({\n"""
insert = """  @override\n  Future<List<Map<String, dynamic>>> getCareEvents({\n    required DateTime fromDate,\n    required DateTime toDate,\n  }) async {\n    try {\n      return await super.getCareEvents(fromDate: fromDate, toDate: toDate);\n    } on LifeMateApiException catch (error) {\n      if (!_canUseOwnerCacheFor(error)) rethrow;\n      final runtime = _activeSharedRuntime();\n      if (runtime == null) rethrow;\n      List<LifeMateLocalProjectionRecord> records;\n      try {\n        records = await runtime.careEventProjections();\n      } catch (_) {\n        throw error;\n      }\n      return records\n          .map((record) => Map<String, dynamic>.from(record.payload))\n          .where(\n            (value) => _careEventInLocalDateRange(\n              value,\n              fromDate: fromDate,\n              toDate: toDate,\n            ),\n          )\n          .toList(growable: false);\n    }\n  }\n\n  @override\n  Future<List<Map<String, dynamic>>> getDoseOccurrences({\n"""
if anchor not in text:
    raise SystemExit('getDoseOccurrences anchor not found')
text = text.replace(anchor, insert, 1)

anchor = """  static bool _canUseOwnerCacheFor(LifeMateApiException error) =>\n"""
insert = """  static bool _careEventInLocalDateRange(\n    Map<String, dynamic> value, {\n    required DateTime fromDate,\n    required DateTime toDate,\n  }) {\n    final raw = value['scheduledLocalDate']?.toString().trim() ?? '';\n    final parsed = DateTime.tryParse(raw);\n    if (parsed == null) return false;\n    final eventDate = DateTime(parsed.year, parsed.month, parsed.day);\n    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);\n    final to = DateTime(toDate.year, toDate.month, toDate.day);\n    return !eventDate.isBefore(from) && !eventDate.isAfter(to);\n  }\n\n  static bool _canUseOwnerCacheFor(LifeMateApiException error) =>\n"""
if anchor not in text:
    raise SystemExit('_canUseOwnerCacheFor anchor not found')
text = text.replace(anchor, insert, 1)
path.write_text(text)

Path('tools/hotfix/apply_offline832_care_event_read_fallback.py').unlink()
Path('.github/workflows/offline832-care-event-read-fallback-patch.yml').unlink()
