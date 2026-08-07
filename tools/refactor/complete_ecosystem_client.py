from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


path = Path("packages/lifemate_client/lib/src/lifemate_api_client.dart")
text = path.read_text(encoding="utf-8")

text = replace_once(
    text,
    "import 'package:http/http.dart' as http;\n\nimport 'reminder_lead_time.dart';\n",
    "import 'package:http/http.dart' as http;\n\nimport 'capabilities.dart';\nimport 'reminder_lead_time.dart';\n",
    "capabilities import",
)

anchor = "  Future<Map<String, dynamic>> getCurrentUser() async =>\n      _asObject(await _send('GET', '/api/v1/me', retryable: true));\n\n"
addition = anchor + """  Future<LifeMateCapabilitySnapshot> getCapabilities() async =>
      LifeMateCapabilitySnapshot.fromJson(
        _asObject(
          await _send('GET', '/api/v1/capabilities', retryable: true),
        ),
      );

  Future<List<String>> syncExternalIdentities() async {
    final result = _asObject(
      await _send('POST', '/api/v1/me/identities/sync'),
    );
    final providers = result['providers'];
    if (providers is! List) return const <String>[];
    return providers
        .whereType<Object>()
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<LifeMateAccountDeletionStatus> requestAccountDeletion() async =>
      LifeMateAccountDeletionStatus.fromJson(
        _asObject(
          await _send('POST', '/api/v1/account/deletion-requests'),
        ),
      );

  Future<LifeMateAccountDeletionStatus?> getLatestAccountDeletionRequest() async {
    final value = await _send(
      'GET',
      '/api/v1/account/deletion-requests/latest',
      retryable: true,
    );
    if (value == null) return null;
    return LifeMateAccountDeletionStatus.fromJson(_asObject(value));
  }

"""
text = replace_once(text, anchor, addition, "ecosystem client methods")

path.write_text(text, encoding="utf-8")
print("ecosystem client codemod applied")
