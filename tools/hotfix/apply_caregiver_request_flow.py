from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"expected snippet missing in {path}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1))


# Dedicated care-management candidate path: strip the full function slug, not
# only the production prefix (which previously left '-candidate/...' behind).
replace_once(
    "supabase/functions/lifemate-care-management/index.ts",
    'import postgres from "postgres";\n',
    'import postgres from "postgres";\nimport { normalizeCareManagementPath } from "./path_utils.ts";\n',
)
replace_once(
    "supabase/functions/lifemate-care-management/index.ts",
    '    const path = normalizePath(new URL(request.url).pathname);',
    '    const path = normalizeCareManagementPath(new URL(request.url).pathname);',
)
old_normalize = '''function normalizePath(path: string): string {
  const marker = "/lifemate-care-management";
  const index = path.indexOf(marker);
  if (index >= 0) {
    const remaining = path.slice(index + marker.length);
    return remaining || "/";
  }
  return path || "/";
}

'''
replace_once("supabase/functions/lifemate-care-management/index.ts", old_normalize, "")

# Main API: wire caregiver-initiated care requests through the existing
# invitation persistence, clearly separated by contact type.
replace_once(
    "supabase/functions/lifemate-api/index.ts",
    'import { createCareEventStore } from "./care_events.ts";\n',
    'import { createCareEventStore } from "./care_events.ts";\nimport { createCareRequestStore } from "./care_requests.ts";\n',
)
replace_once(
    "supabase/functions/lifemate-api/index.ts",
    'const careEvents = createCareEventStore(databaseUrl);\n',
    'const careEvents = createCareEventStore(databaseUrl);\nconst careRequests = createCareRequestStore(databaseUrl, contactHashingSecret);\n',
)
route_anchor = '''  if (
    request.method === "POST" &&
    path === "/api/v1/care/invitations/qr"
  ) {'''
request_routes = '''  if (request.method === "POST" && path === "/api/v1/care/requests") {
    enforceRateLimit(`care-request:${identity.appUserId}`, 8, 60 * 60_000);
    return json(
      await careRequests.create(identity, await readJsonObject(request)),
      201,
    );
  }
  if (
    request.method === "GET" &&
    path === "/api/v1/care/requests/outgoing"
  ) {
    return json(await careRequests.listOutgoing(identity.appUserId));
  }
  if (
    request.method === "GET" &&
    path === "/api/v1/care/requests/incoming"
  ) {
    const incoming = await careRequests.listIncoming(identity);
    const presented = [];
    for (const item of incoming) {
      const requesterUserId = String(item.requesterUserId ?? "");
      let requesterProfile: Record<string, unknown> = {};
      if (requesterUserId) {
        try {
          requesterProfile = await presentProfile(requesterUserId);
        } catch {
          requesterProfile = {};
        }
      }
      presented.push({
        ...item,
        requesterDisplayName:
          requesterProfile.displayName ?? item.requesterDisplayName,
        requesterAvatarKey:
          requesterProfile.avatarKey ?? item.requesterAvatarKey ?? null,
        requesterProfilePhotoUrl: requesterProfile.profilePhotoUrl ?? null,
      });
    }
    return json(presented);
  }
  const careRequestMatch = path.match(
    /^\\/api\\/v1\\/care\\/requests\\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "DELETE" && careRequestMatch) {
    enforceRateLimit(`care-request-cancel:${identity.appUserId}`, 20, 60 * 60_000);
    await careRequests.cancel(identity.appUserId, careRequestMatch[1]);
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  const careRequestResponseMatch = path.match(
    /^\\/api\\/v1\\/care\\/requests\\/([0-9a-f-]{36})\\/respond$/i,
  );
  if (request.method === "POST" && careRequestResponseMatch) {
    enforceRateLimit(`care-request-respond:${identity.appUserId}`, 20, 60 * 60_000);
    return json(
      await careRequests.respond(
        identity,
        careRequestResponseMatch[1],
        await readJsonObject(request),
      ),
    );
  }

'''
replace_once("supabase/functions/lifemate-api/index.ts", route_anchor, request_routes + route_anchor)

# Shared Flutter client contract.
client_anchor = '''  Future<void> revokeCareInvitation({required String invitationId}) async {
    await _send(
      'DELETE',
      '/api/v1/care/invitations/$invitationId',
      retryable: true,
    );
  }

'''
client_methods = client_anchor + '''  Future<Map<String, dynamic>> createCareRequest({
    required String email,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/care/requests',
      body: {
        'contactType': 'email',
        'contact': email.trim(),
        'consentVersion': 'care-caregiver-request-v1',
        'confirmConsent': true,
      },
    ),
  );

  Future<List<Map<String, dynamic>>> getOutgoingCareRequests() =>
      _getList('/api/v1/care/requests/outgoing');

  Future<List<Map<String, dynamic>>> getIncomingCareRequests() =>
      _getList('/api/v1/care/requests/incoming');

  Future<Map<String, dynamic>> respondCareRequest({
    required String requestId,
    required bool accept,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/care/requests/$requestId/respond',
      body: {
        'action': accept ? 'accept' : 'reject',
        if (accept) ...{
          'consentVersion': 'care-patient-consent-v1',
          'confirmConsent': true,
        },
      },
    ),
  );

  Future<void> revokeCareRequest({required String requestId}) async {
    await _send(
      'DELETE',
      '/api/v1/care/requests/$requestId',
      retryable: true,
    );
  }

'''
replace_once("packages/lifemate_client/lib/src/lifemate_api_client.dart", client_anchor, client_methods)

# Client regression tests for request direction and consent contracts.
test_file = Path("packages/lifemate_client/test/lifemate_api_client_test.dart")
test_text = test_file.read_text()
insert_before = "  test('missing session fails before a network request', () async {"
new_tests = r'''  test('caregiver care request sends caregiver consent contract', () async {
    late http.Request observed;
    late Map<String, dynamic> body;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        observed = request;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'request-1', 'status': 'pending'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.createCareRequest(email: ' patient@example.com ');

    expect(observed.method, 'POST');
    expect(observed.url.path, '/api/v1/care/requests');
    expect(body['contact'], 'patient@example.com');
    expect(body['consentVersion'], 'care-caregiver-request-v1');
    expect(body['confirmConsent'], isTrue);
  });

  test('patient acceptance sends explicit patient consent', () async {
    late Map<String, dynamic> body;
    final api = LifeMateApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: () => 'access-token',
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'request-1', 'status': 'accepted'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.respondCareRequest(requestId: 'request-1', accept: true);

    expect(body['action'], 'accept');
    expect(body['consentVersion'], 'care-patient-consent-v1');
    expect(body['confirmConsent'], isTrue);
  });

'''
if insert_before not in test_text:
    raise SystemExit("client test insertion anchor missing")
test_file.write_text(test_text.replace(insert_before, new_tests + insert_before, 1))

# CareMate: load outgoing requests, expose a polished email request card, and
# preserve the existing code/QR invitation acceptance flow.
caremate = "caremate/lib/screens/feature_preview_screen.dart"
replace_once(
    caremate,
    "import '../widgets/care_profile_mask_selector.dart';\n",
    "import '../widgets/care_profile_mask_selector.dart';\nimport '../widgets/care_request_card.dart';\n",
)
replace_once(
    caremate,
    "  bool _accepting = false;\n",
    "  bool _accepting = false;\n  bool _requestingCare = false;\n",
)
replace_once(
    caremate,
    "  List<Map<String, dynamic>> _relationships = const [];\n  List<Map<String, dynamic>> _doses = const [];\n",
    "  List<Map<String, dynamic>> _relationships = const [];\n  List<Map<String, dynamic>> _outgoingCareRequests = const [];\n  List<Map<String, dynamic>> _doses = const [];\n",
)
replace_once(
    caremate,
    '''      final values = await Future.wait([
        api.getCurrentUser(),
        api.getCareRelationships(),
      ]);''',
    '''      final values = await Future.wait([
        api.getCurrentUser(),
        api.getCareRelationships(),
        api.getOutgoingCareRequests(),
      ]);''',
)
replace_once(
    caremate,
    '''        _relationships = relationships;
        _selectedRelationshipId = selectedId;
      });''',
    '''        _relationships = relationships;
        _outgoingCareRequests = values[2] as List<Map<String, dynamic>>;
        _selectedRelationshipId = selectedId;
      });''',
)
method_anchor = "  Future<void> _showAcceptInvitation() async {"
request_methods = r'''  Future<void> _showCareRequestSheet() async {
    final controller = TextEditingController();
    var consent = false;
    final email = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'درخواست مراقبت',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'ایمیل حساب WellMate فرد را وارد کنید. تا وقتی خودش تأیید نکند هیچ اطلاعاتی برای شما باز نمی‌شود.',
                    style: TextStyle(height: 1.6, color: AppColors.secondaryText),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      labelText: 'ایمیل WellMate',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      filled: true,
                      fillColor: const Color(0xFFF3F7FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    value: consent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setSheetState(() => consent = value ?? false),
                    title: const Text(
                      'می‌دانم دسترسی فقط با رضایت خود فرد فعال می‌شود و هر زمان قابل لغو است.',
                      style: TextStyle(fontSize: 12.5, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: consent && _looksLikeEmail(controller.text)
                          ? () => Navigator.pop(
                              sheetContext,
                              controller.text.trim(),
                            )
                          : null,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('ارسال درخواست'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (email == null || !mounted) return;

    setState(() => _requestingCare = true);
    try {
      await context.read<LifeMateApiClient>().createCareRequest(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('درخواست ارسال شد؛ منتظر تأیید در WellMate بمانید.'),
        ),
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'care_request_target_not_found' =>
          'حساب WellMate فعالی با این ایمیل پیدا نشد.',
        'care_request_already_pending' =>
          'برای این فرد یک درخواست در انتظار دارید.',
        'care_relationship_already_active' =>
          'شما همین حالا مراقب این فرد هستید.',
        'self_care_request_not_allowed' =>
          'نمی‌توانید برای حساب خودتان درخواست مراقبت بفرستید.',
        _ => _friendlyApiError(error),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _requestingCare = false);
    }
  }

  Future<void> _cancelCareRequest(Map<String, dynamic> request) async {
    final id = request['id']?.toString();
    if (id == null || id.isEmpty) return;
    try {
      await context.read<LifeMateApiClient>().revokeCareRequest(requestId: id);
      await _refresh();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyApiError(error))),
      );
    }
  }

'''
replace_once(caremate, method_anchor, request_methods + method_anchor)
family_anchor = '''  Widget _buildFamilyCare(_FeatureDefinition feature) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _accepting ? null : _showAcceptInvitation,
            icon: _accepting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('پذیرش دعوت مراقبت'),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle(
          title: 'تیم مراقبت',
          subtitle:
              'روابط فعال و قابل لغو، بدون نمایش اطلاعات خارج از رضایت بیمار.',
        ),'''
family_new = '''  Widget _buildFamilyCare(_FeatureDefinition feature) {
    final pendingRequests = _outgoingCareRequests
        .where((request) => request['status']?.toString() == 'pending')
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'افراد تحت مراقبت',
          subtitle: 'ارتباط‌های فعال شما؛ هر فرد فقط اطلاعات مجاز خودش را دارد.',
        ),'''
replace_once(caremate, family_anchor, family_new)
# Insert request card after relationship list and before development card.
insert_anchor = '''        const SizedBox(height: 8),
        _DevelopmentCard(
          accent: feature.accent,'''
insert_new = '''        const SizedBox(height: 10),
        CareRequestCard(
          loading: _requestingCare,
          pendingRequests: pendingRequests,
          onRequest: _showCareRequestSheet,
          onCancel: _cancelCareRequest,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFF1F5FF),
                child: Icon(Icons.qr_code_rounded, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'دعوت از طرف WellMate داری؟',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'کد یا QR دعوت را بپذیر تا ارتباط مراقبتی فعال شود.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _accepting ? null : _showAcceptInvitation,
                child: const Text('پذیرش'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DevelopmentCard(
          accent: feature.accent,'''
replace_once(caremate, insert_anchor, insert_new)
# Email helper before dose time helper.
replace_once(
    caremate,
    "  static String _doseTime(Map<String, dynamic> dose) {",
    "  static bool _looksLikeEmail(String value) {\n    final email = value.trim();\n    final at = email.indexOf('@');\n    return at > 0 && at < email.length - 3 && email.contains('.', at);\n  }\n\n  static String _doseTime(Map<String, dynamic> dose) {",
)

# WellMate incoming request list and response actions.
wellmate = "wellmate/lib/screens/profile/care_access_screen.dart"
replace_once(
    wellmate,
    "import 'care_access_settings_screen.dart';\n",
    "import 'care_access_settings_screen.dart';\nimport 'incoming_care_request_card.dart';\n",
)
replace_once(
    wellmate,
    "  List<Map<String, dynamic>> _relationships = const [];\n  final Set<String> _cancellingInvitationIds = <String>{};\n",
    "  List<Map<String, dynamic>> _relationships = const [];\n  List<Map<String, dynamic>> _incomingRequests = const [];\n  final Set<String> _cancellingInvitationIds = <String>{};\n  final Set<String> _respondingCareRequestIds = <String>{};\n",
)
replace_once(
    wellmate,
    '''      final results = await Future.wait([
        api.getCurrentUser(),
        api.getOutgoingCareInvitations(),
        api.getCareRelationships(),
      ]);''',
    '''      final results = await Future.wait([
        api.getCurrentUser(),
        api.getOutgoingCareInvitations(),
        api.getCareRelationships(),
        api.getIncomingCareRequests(),
      ]);''',
)
replace_once(
    wellmate,
    '''        _invitations = results[1] as List<Map<String, dynamic>>;
        _relationships = relationships;
      });''',
    '''        _invitations = results[1] as List<Map<String, dynamic>>;
        _relationships = relationships;
        _incomingRequests = results[3] as List<Map<String, dynamic>>;
      });''',
)
respond_anchor = "  Future<void> _openInviteSheet() async {"
respond_method = r'''  Future<void> _respondToCareRequest(
    Map<String, dynamic> request, {
    required bool accept,
  }) async {
    final id = request['id']?.toString();
    if (id == null || id.isEmpty || _respondingCareRequestIds.contains(id)) {
      return;
    }
    if (accept) {
      final name = request['requesterDisplayName']?.toString() ?? 'این فرد';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('تأیید درخواست مراقبت'),
          content: Text(
            'با تأیید، $name به‌عنوان مراقب شما فعال می‌شود. دسترسی‌های حساس مثل تقویم بانوان و مدیریت پرونده سلامت همچنان جداگانه و فقط با اجازه خودتان فعال می‌شوند.',
            style: const TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('فعلاً نه'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تأیید مراقب'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _respondingCareRequestIds.add(id));
    try {
      await context.read<LifeMateApiClient>().respondCareRequest(
        requestId: id,
        accept: accept,
      );
      if (!mounted) return;
      _notice(
        type: LifeMateNoticeType.success,
        title: accept ? 'مراقب اضافه شد' : 'درخواست رد شد',
        message: accept
            ? 'ارتباط مراقبتی فعال شد؛ حالا می‌توانید دسترسی‌هایش را تنظیم کنید.'
            : 'این درخواست دیگر فعال نیست.',
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      _notice(
        type: LifeMateNoticeType.error,
        title: 'انجام نشد',
        message: switch (error.code) {
          'care_request_expired' => 'این درخواست منقضی شده است.',
          'care_request_not_pending' => 'این درخواست قبلاً بررسی شده است.',
          _ => 'دوباره تلاش کنید یا اتصال اینترنت را بررسی کنید.',
        },
      );
    } finally {
      if (mounted) setState(() => _respondingCareRequestIds.remove(id));
    }
  }

'''
replace_once(wellmate, respond_anchor, respond_method + respond_anchor)
# Build incoming list and count.
replace_once(
    wellmate,
    '''    final pending = _invitations
        .where((invitation) => invitation['status'] == 'pending')
        .toList(growable: false);''',
    '''    final pending = _invitations
        .where((invitation) => invitation['status'] == 'pending')
        .toList(growable: false);
    final incoming = _incomingRequests
        .where((request) => request['status'] == 'pending')
        .toList(growable: false);''',
)
replace_once(
    wellmate,
    '''            _SectionHeader(
              title: 'درخواست‌های جدید',
              count: 0,
              isPersian: isPersian,
            ),
            const SizedBox(height: 10),
            const _NoIncomingRequestsCard(),''',
    '''            _SectionHeader(
              title: 'درخواست‌های جدید',
              count: incoming.length,
              isPersian: isPersian,
            ),
            const SizedBox(height: 10),
            if (incoming.isEmpty)
              const _NoIncomingRequestsCard()
            else
              ...incoming.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: IncomingCareRequestCard(
                    request: request,
                    loading: _respondingCareRequestIds.contains(
                      request['id']?.toString(),
                    ),
                    onAccept: () =>
                        _respondToCareRequest(request, accept: true),
                    onReject: () =>
                        _respondToCareRequest(request, accept: false),
                  ),
                ),
              ),''',
)
replace_once(
    wellmate,
    "درخواست جدیدی برای بررسی ندارید. وقتی قابلیت درخواست مراقبت از سمت CareMate فعال شود، درخواست واقعی هر فرد همین‌جا نمایش داده می‌شود.",
    "درخواست جدیدی برای بررسی ندارید. اگر کسی از CareMate درخواست مراقبت بفرستد، نام و تصویرش همین‌جا نمایش داده می‌شود.",
)

# Lightweight source-level UX regression contracts.
Path("caremate/test/care_request_flow_contract_test.dart").write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('care page exposes caregiver initiated email request flow', () {
    final source = File('lib/screens/feature_preview_screen.dart').readAsStringSync();
    expect(source, contains('ارسال درخواست مراقبت'));
    expect(source, contains('createCareRequest(email: email)'));
    expect(source, contains('getOutgoingCareRequests()'));
  });
}
''')
Path("wellmate/test/incoming_care_request_contract_test.dart").write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('incoming caregiver request only shows accept and reject for real rows', () {
    final source = File('lib/screens/profile/care_access_screen.dart').readAsStringSync();
    expect(source, contains('getIncomingCareRequests()'));
    expect(source, contains('IncomingCareRequestCard'));
    expect(source, contains('_respondToCareRequest(request, accept: true)'));
    expect(source, contains('_respondToCareRequest(request, accept: false)'));
  });
}
''')

# Delete this one-shot patch script before the verified commit.
Path(__file__).unlink()
