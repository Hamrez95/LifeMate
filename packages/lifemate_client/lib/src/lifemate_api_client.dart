import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'capabilities.dart';
import 'reminder_lead_time.dart';
import 'recurrence.dart';

typedef AccessTokenProvider = String? Function();

/// Stable category values shared with the private Health Record API.
enum LifeMateHealthDocumentCategory {
  prescription, labResult, imaging, visit, injection, discharge, vaccination, other;

  String get wireValue => switch (this) {
    prescription => 'prescription', labResult => 'lab_result', imaging => 'imaging',
    visit => 'visit', injection => 'injection', discharge => 'discharge',
    vaccination => 'vaccination', other => 'other',
  };

  static LifeMateHealthDocumentCategory fromWire(String value) =>
      LifeMateHealthDocumentCategory.values.firstWhere(
        (category) => category.wireValue == value,
        orElse: () => throw FormatException('Unknown Health Record category.'),
      );
}

enum LifeMateHealthDocumentContextType {
  treatmentPlan, careEvent;

  String get wireValue => switch (this) {
    treatmentPlan => 'treatment_plan', careEvent => 'care_event',
  };
}

class LifeMateHealthDocument {
  const LifeMateHealthDocument({
    required this.id, required this.contentType, required this.byteSize,
    required this.category, required this.capturedOn, required this.createdAtUtc,
    required this.links, required this.sourceProduct,
  });

  factory LifeMateHealthDocument.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final contentType = json['contentType']?.toString() ?? '';
    final byteSize = json['byteSize'];
    final category = json['category']?.toString() ?? '';
    final sourceProduct = json['sourceProduct']?.toString().trim() ?? '';
    final createdAtUtc = DateTime.tryParse(json['createdAtUtc']?.toString() ?? '');
    if (id.isEmpty || contentType.isEmpty || sourceProduct.isEmpty ||
        byteSize is! num || createdAtUtc == null) {
      throw const FormatException('Invalid Health Record document payload.');
    }
    final links = (json['links'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    return LifeMateHealthDocument(
      id: id, contentType: contentType, byteSize: byteSize.toInt(),
      category: LifeMateHealthDocumentCategory.fromWire(category),
      capturedOn: DateTime.tryParse(json['capturedOn']?.toString() ?? ''),
      createdAtUtc: createdAtUtc.toUtc(), links: links,
      sourceProduct: sourceProduct,
    );
  }

  final String id;
  final String contentType;
  final int byteSize;
  final LifeMateHealthDocumentCategory category;
  final DateTime? capturedOn;
  final DateTime createdAtUtc;
  final List<Map<String, dynamic>> links;
  final String sourceProduct;
}

class LifeMateHealthDocumentDownload {
  const LifeMateHealthDocumentDownload({
    required this.document, required this.signedUrl, required this.expiresIn,
  });

  final LifeMateHealthDocument document;
  final Uri signedUrl;
  final Duration expiresIn;
}

/// A bounded slice of the private Health Record timeline. `nextCursor` is an
/// opaque server value and must be forwarded unchanged; it is not a document
/// identifier or Storage path.
class LifeMateHealthDocumentPage {
  const LifeMateHealthDocumentPage({
    required this.items,
    required this.nextCursor,
  });

  final List<LifeMateHealthDocument> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

class LifeMateApiException implements Exception {
  const LifeMateApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'LifeMateApiException($statusCode, $code): $message';
}

class LifeMateApiClient {
  LifeMateApiClient({
    required Uri baseUri,
    required AccessTokenProvider accessToken,
    http.Client? httpClient,
  }) : _baseUri = baseUri,
       _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final AccessTokenProvider _accessToken;
  final http.Client _http;
  final Map<String, String> _pendingMutationKeys = <String, String>{};
  static const _requestTimeout = Duration(seconds: 20);
  static const _retryBudget = Duration(seconds: 30);
  static const _retryBaseDelay = Duration(milliseconds: 250);
  static const _retryMaxDelay = Duration(seconds: 2);
  static const _transientStatusCodes = <int>{502, 503, 504};
  static final Random _retryRandom = Random.secure();

  static String createClientRequestId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<Map<String, dynamic>> bootstrapUser({
    required String? displayName,
    required String? email,
    String locale = 'fa',
    String timeZone = 'Asia/Tehran',
  }) async {
    final value = await _send(
      'POST',
      '/api/v1/users/bootstrap',
      body: {
        'displayName': displayName,
        'phoneNumber': null,
        'email': email,
        'locale': locale,
        'timeZone': timeZone,
      },
    );
    return _asObject(value);
  }

  Future<Map<String, dynamic>> getCurrentUser() async =>
      _asObject(await _send('GET', '/api/v1/me', retryable: true));

  Future<LifeMateCapabilitySnapshot> getCapabilities() async =>
      LifeMateCapabilitySnapshot.fromJson(
        _asObject(await _send('GET', '/api/v1/capabilities', retryable: true)),
      );

  Future<List<String>> syncExternalIdentities() async {
    final result = _asObject(await _send('POST', '/api/v1/me/identities/sync'));
    final providers = result['providers'];
    if (providers is! List) return const <String>[];
    return providers
        .whereType<Object>()
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> exportAccountData() async =>
      _asObject(await _send('GET', '/api/v1/account/data-export'));

  Future<LifeMateAccountDeletionStatus> requestAccountDeletion() async =>
      LifeMateAccountDeletionStatus.fromJson(
        _asObject(await _send('POST', '/api/v1/account/deletion-requests')),
      );

  Future<LifeMateAccountDeletionStatus?>
  getLatestAccountDeletionRequest() async {
    final value = await _send(
      'GET',
      '/api/v1/account/deletion-requests/latest',
      retryable: true,
    );
    if (value == null) return null;
    return LifeMateAccountDeletionStatus.fromJson(_asObject(value));
  }

  Future<Map<String, dynamic>> getCurrentProfile() async =>
      _asObject(await _send('GET', '/api/v1/me/profile', retryable: true));

  /// Commerce data is server-authoritative; the client never supplies price,
  /// discount, trial duration, quota or conversion credit.
  Future<Map<String, dynamic>> getSubscriptionSnapshot() async =>
      _asObject(await _send('GET', '/api/v1/subscription/snapshot', retryable: true));

  Future<Map<String, dynamic>> getPeriodAccessSnapshot() async =>
      _asObject(await _send('GET', '/api/v1/subscription/period-access', retryable: true));

  Future<Map<String, dynamic>> startPeriodTrial({
    required String idempotencyKey,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/subscription/period-trial',
      body: const <String, dynamic>{},
      retryable: true,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<Map<String, dynamic>> claimSubscriptionGift({
    required String claimToken,
    required String idempotencyKey,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/subscription/gifts/claim',
      body: {'claimToken': claimToken.trim()},
      retryable: true,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<Map<String, dynamic>> convertPeriodToCocoon({
    required String idempotencyKey,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/subscription/period-to-cocoon/convert',
      body: const {'confirmed': true},
      retryable: true,
      idempotencyKey: idempotencyKey,
    ),
  );

  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => _asObject(
    await _send(
      'GET',
      '/api/v1/home-snapshot',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      retryable: true,
    ),
  );

  Future<Map<String, dynamic>> uploadCurrentProfilePhoto({
    required Uint8List bytes,
    required String contentType,
  }) async => _asObject(
    await _sendBinary(
      'PUT',
      '/api/v1/me/profile/photo',
      bytes: bytes,
      contentType: contentType,
    ),
  );

  Future<LifeMateHealthDocumentPage> getHealthDocumentPage({
    String? personId,
    LifeMateHealthDocumentCategory? category,
    String? sourceProduct,
    DateTime? fromDate,
    DateTime? toDate,
    String? cursor,
    int limit = 25,
  }) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100.');
    }
    final payload = _asObject(
      await _send(
        'GET',
        '/api/v1/health-record/documents',
        query: {
          if (personId?.trim().isNotEmpty ?? false) 'personId': personId!.trim(),
          if (category != null) 'category': category.wireValue,
          if (sourceProduct?.trim().isNotEmpty ?? false)
            'sourceProduct': sourceProduct!.trim(),
          if (fromDate != null) 'fromDate': _date(fromDate),
          if (toDate != null) 'toDate': _date(toDate),
          if (cursor?.trim().isNotEmpty ?? false) 'cursor': cursor!.trim(),
          'limit': '$limit',
        },
        retryable: true,
      ),
    );
    final items = payload['items'];
    if (items is! List) {
      throw const FormatException('Invalid Health Record document list.');
    }
    final nextCursor = payload['nextCursor'];
    if (nextCursor != null && nextCursor is! String) {
      throw const FormatException('Invalid Health Record document cursor.');
    }
    return LifeMateHealthDocumentPage(
      items: items
        .map((value) => LifeMateHealthDocument.fromJson(_asObject(value)))
        .toList(growable: false),
      nextCursor: nextCursor as String?,
    );
  }

  Future<List<LifeMateHealthDocument>> getHealthDocuments() async {
    return (await getHealthDocumentPage(limit: 100)).items;
  }

  Future<LifeMateHealthDocument> uploadHealthDocument({
    required Uint8List bytes,
    required String contentType,
    required LifeMateHealthDocumentCategory category,
    DateTime? capturedOn,
    LifeMateHealthDocumentContextType? contextType,
    String? contextId,
  }) async {
    if (bytes.isEmpty || bytes.lengthInBytes > 15 * 1024 * 1024) {
      throw ArgumentError.value(
        bytes,
        'bytes',
        'Health Record documents must be between 1 byte and 15 MB.',
      );
    }
    final normalizedContextId = contextId?.trim();
    final hasContextId =
        normalizedContextId != null && normalizedContextId.isNotEmpty;
    if ((contextType == null) == hasContextId) {
      throw ArgumentError(
        'A Health Record context type and identifier must be supplied together.',
      );
    }
    final result = _asObject(
      await _sendBinary(
        'PUT',
        '/api/v1/health-record/documents',
        bytes: bytes,
        contentType: contentType,
        headers: {
          'X-Health-Document-Category': category.wireValue,
          if (capturedOn != null)
            'X-Health-Document-Captured-On': _date(capturedOn),
          if (contextType != null)
            'X-Health-Document-Context-Type': contextType.wireValue,
          if (normalizedContextId != null && normalizedContextId.isNotEmpty)
            'X-Health-Document-Context-Id': normalizedContextId,
        },
      ),
    );
    return LifeMateHealthDocument.fromJson(result);
  }

  Future<LifeMateHealthDocumentDownload> getHealthDocumentDownload(
    String documentId,
  ) async {
    final payload = _asObject(
      await _send(
        'GET',
        '/api/v1/health-record/documents/${documentId.trim()}/download',
        retryable: true,
      ),
    );
    final signedUrl = Uri.tryParse(payload['signedUrl']?.toString() ?? '');
    final expiresIn = payload['expiresInSeconds'];
    if (signedUrl == null || expiresIn is! num || expiresIn <= 0) {
      throw const FormatException('Invalid Health Record download payload.');
    }
    return LifeMateHealthDocumentDownload(
      document: LifeMateHealthDocument.fromJson(payload),
      signedUrl: signedUrl,
      expiresIn: Duration(seconds: expiresIn.toInt()),
    );
  }

  Future<Map<String, dynamic>> getHealthDocumentSharingPermission({
  required String relationshipId,
}) async => _asObject(
  await _send(
    'GET',
    '/api/v1/health-record/relationships/${relationshipId.trim()}/document-sharing',
    retryable: true,
  ),
);

Future<Map<String, dynamic>> updateHealthDocumentSharingPermission({
  required String relationshipId,
  required bool enabled,
  bool confirmConsent = false,
}) async => _asObject(
  await _send(
    'PATCH',
    '/api/v1/health-record/relationships/${relationshipId.trim()}/document-sharing',
    body: {
      'canViewDocuments': enabled,
      if (enabled) ...{
        'confirmConsent': confirmConsent,
        'consentVersion': 'health-record-documents-sharing-v1',
      },
    },
  ),
);

  Future<Map<String, dynamic>> deleteCurrentProfilePhoto() async =>
      _asObject(await _send('DELETE', '/api/v1/me/profile/photo'));

  Future<Map<String, dynamic>> updateCurrentProfile({
    required int version,
    required String displayName,
    String? phoneNumber,
    required String locale,
    required String timeZone,
    required String avatarKey,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/me/profile',
      body: {
        'version': version,
        'displayName': displayName.trim(),
        'phoneNumber': _emptyToNull(phoneNumber),
        'locale': locale.trim(),
        'timeZone': timeZone.trim(),
        'avatarKey': avatarKey.trim(),
      },
    ),
  );

  Future<List<Map<String, dynamic>>> getMedications() =>
      _getList('/api/v1/medications');

  Future<Map<String, dynamic>> createMedication({
    required String name,
    String? strengthText,
    String? form,
    String? notes,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/medications',
      body: {
        'name': name.trim(),
        'strengthText': _emptyToNull(strengthText),
        'form': _emptyToNull(form),
        'notes': _emptyToNull(notes),
      },
    ),
  );

  Future<List<Map<String, dynamic>>> getTreatmentPlans() =>
      _getList('/api/v1/treatment-plans');

  Future<Map<String, dynamic>> createTreatmentPlan({
    required String medicationId,
    required String doseText,
    required DateTime startDate,
    DateTime? endDate,
    required String timeZone,
    required List<Map<String, String>> schedules,
    RecurrenceRule recurrence = const RecurrenceRule.none(),
    String? recurrenceStartLocalTime,
    String? instructions,
    int patientReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultPatientMinutes,
    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
    String? clientRequestId,
  }) async {
    if (recurrence.enabled &&
        (recurrenceStartLocalTime == null ||
            recurrenceStartLocalTime.trim().isEmpty)) {
      throw ArgumentError.value(
        recurrenceStartLocalTime,
        'recurrenceStartLocalTime',
        'Recurring treatment plans require a local anchor time.',
      );
    }
    return _asObject(
      await _send(
        'POST',
        '/api/v1/treatment-plans',
        body: {
          'medicationId': medicationId,
          'doseText': doseText.trim(),
          'instructions': _emptyToNull(instructions),
          'startDate': _date(startDate),
          'endDate': endDate == null ? null : _date(endDate),
          'timeZone': timeZone,
          'schedules': recurrence.enabled ? const [] : schedules,
          'recurrence': recurrence.toJson(),
          'recurrenceStartLocalTime': recurrence.enabled
              ? recurrenceStartLocalTime!.trim()
              : null,
          'patientReminderMinutesBefore': patientReminderMinutesBefore,
          'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
        },
        idempotencyKey: clientRequestId,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> getCareEvents({
    required DateTime fromDate,
    required DateTime toDate,
  }) => _getList(
    '/api/v1/care-events',
    query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
  );

  Future<Map<String, dynamic>> createCareEvent({
    required String clientRequestId,
    required String eventType,
    required String title,
    required DateTime scheduledLocalDate,
    required String scheduledLocalTime,
    required String timeZone,
    String? providerName,
    String? specialty,
    String? medicationName,
    String? doseText,
    String? administrationRoute,
    String? reason,
    String? instructions,
    String? centerName,
    String? addressLine,
    String? phoneNumber,
    RecurrenceRule recurrence = const RecurrenceRule.none(),
    int patientReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultPatientMinutes,
    int caregiverReminderMinutesBefore =
        LifeMateReminderLeadTimes.defaultCaregiverMinutes,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/care-events',
      body: {
        'clientRequestId': clientRequestId,
        'eventType': eventType.trim().toLowerCase(),
        'title': title.trim(),
        'providerName': _emptyToNull(providerName),
        'specialty': _emptyToNull(specialty),
        'medicationName': _emptyToNull(medicationName),
        'doseText': _emptyToNull(doseText),
        'administrationRoute': _emptyToNull(administrationRoute),
        'reason': _emptyToNull(reason),
        'instructions': _emptyToNull(instructions),
        'centerName': _emptyToNull(centerName),
        'addressLine': _emptyToNull(addressLine),
        'phoneNumber': _emptyToNull(phoneNumber),
        'scheduledLocalDate': _date(scheduledLocalDate),
        'recurrence': recurrence.toJson(),
        'scheduledLocalTime': scheduledLocalTime.trim(),
        'timeZone': timeZone.trim(),
        'patientReminderMinutesBefore': patientReminderMinutesBefore,
        'caregiverReminderMinutesBefore': caregiverReminderMinutesBefore,
      },
      retryable: true,
      idempotencyKey: clientRequestId,
    ),
  );

  Future<List<Map<String, dynamic>>> getDoseOccurrences({
    required DateTime fromDate,
    required DateTime toDate,
  }) => _getList(
    '/api/v1/dose-occurrences',
    query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
  );

  Future<Map<String, dynamic>> reportDose({
    required String occurrenceId,
    required String clientRequestId,
    required int version,
    required String status,
    required DateTime occurredAtUtc,
  }) async {
    final value = await _send(
      'POST',
      '/api/v1/dose-occurrences/$occurrenceId/report',
      body: {
        'clientRequestId': clientRequestId,
        'version': version,
        'status': status,
        'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
      },
      retryable: true,
      idempotencyKey: clientRequestId,
    );
    return _asObject(value);
  }

  Future<List<Map<String, dynamic>>> getCareRelationships() =>
      _getList('/api/v1/care/relationships');

  Future<Map<String, dynamic>> createCareInvitation({
    required String email,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/care/invitations',
      body: {
        'contactType': 'email',
        'contact': email.trim(),
        'consentVersion': 'care-patient-consent-v1',
        'confirmConsent': true,
      },
    ),
  );

  Future<Map<String, dynamic>> createPhoneCareInvitation({
    required String phone,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/care/invitations',
      body: {
        'contactType': 'phone',
        'contact': phone.trim(),
        'consentVersion': 'care-patient-consent-v1',
        'confirmConsent': true,
      },
    ),
  );

  Future<Map<String, dynamic>> createQrCareInvitation() async => _asObject(
    await _send(
      'POST',
      '/api/v1/care/invitations/qr',
      body: {
        'consentVersion': 'care-patient-consent-v1',
        'confirmConsent': true,
      },
    ),
  );

  Future<List<Map<String, dynamic>>> getOutgoingCareInvitations() =>
      _getList('/api/v1/care/invitations');

  Future<void> revokeCareInvitation({required String invitationId}) async {
    await _send(
      'DELETE',
      '/api/v1/care/invitations/$invitationId',
      retryable: true,
    );
  }

  Future<Map<String, dynamic>> createCareRequest({
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
    await _send('DELETE', '/api/v1/care/requests/$requestId', retryable: true);
  }

  Future<Map<String, dynamic>> acceptCareInvitation({
    required String token,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/care/invitations/accept',
      body: {
        'token': token.trim(),
        'consentVersion': 'care-caregiver-consent-v1',
        'confirmConsent': true,
      },
      retryable: true,
    ),
  );

  Future<void> revokeCareRelationship({required String relationshipId}) async {
    await _send(
      'DELETE',
      '/api/v1/care/relationships/$relationshipId',
      retryable: true,
    );
  }

  Future<List<Map<String, dynamic>>> getCareRecipientDoseOccurrences({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) => _getList(
    '/api/v1/care/patients/$patientUserId/dose-occurrences',
    query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
  );

  Future<List<Map<String, dynamic>>> getCareRecipientCareEvents({
    required String patientUserId,
    required DateTime fromDate,
    required DateTime toDate,
  }) => _getList(
    '/api/v1/care/patients/$patientUserId/care-events',
    query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
  );

  Future<List<Map<String, dynamic>>> getWomenCompanionPrivacyScopes() =>
      _getList('/api/v1/women-calendar/companion-privacy');

  Future<Map<String, dynamic>> updateWomenCompanionPrivacyScopes({
    required String relationshipId,
    required int version,
    required Map<String, bool> scopes,
  }) async => _asObject(await _send(
    'PUT',
    '/api/v1/women-calendar/companion-privacy/$relationshipId',
    body: {'version': version, 'scopes': scopes},
  ));

  Future<Map<String, dynamic>> getWomenCalendarProfile() async => _asObject(
    await _send('GET', '/api/v1/women-calendar/profile', retryable: true),
  );

  Future<Map<String, dynamic>> getWomenCalendarDashboard({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => _asObject(
    await _send(
      'GET',
      '/api/v1/women-calendar/dashboard',
      query: {'fromDate': _date(fromDate), 'toDate': _date(toDate)},
      retryable: true,
    ),
  );

  Future<Map<String, dynamic>> updateWomenCalendarProfile({
    required int version,
    required bool enabled,
    required DateTime? lastPeriodStart,
    required int cycleLength,
    required int periodLength,
    required bool remindersEnabled,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/women-calendar/profile',
      body: {
        'version': version,
        'enabled': enabled,
        'lastPeriodStart': lastPeriodStart == null
            ? null
            : _date(lastPeriodStart),
        'cycleLength': cycleLength,
        'periodLength': periodLength,
        'remindersEnabled': remindersEnabled,
      },
    ),
  );

  Future<List<Map<String, dynamic>>> getWomenCalendarEpisodes() =>
      _getList('/api/v1/women-calendar/episodes');

  Future<Map<String, dynamic>> createWomenCalendarEpisode({
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/women-calendar/episodes',
      body: {
        'startedOn': _date(startedOn),
        'endedOn': endedOn == null ? null : _date(endedOn),
        'privateNotes': _emptyToNull(privateNotes),
      },
    ),
  );

  Future<Map<String, dynamic>> updateWomenCalendarEpisode({
    required String episodeId,
    required int version,
    required DateTime startedOn,
    required DateTime? endedOn,
    String? privateNotes,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/women-calendar/episodes/$episodeId',
      body: {
        'version': version,
        'startedOn': _date(startedOn),
        'endedOn': endedOn == null ? null : _date(endedOn),
        'privateNotes': _emptyToNull(privateNotes),
      },
    ),
  );

  Future<void> deleteWomenCalendarEpisode({required String episodeId}) async {
    await _send('DELETE', '/api/v1/women-calendar/episodes/$episodeId');
  }

  Future<Map<String, dynamic>> updateCareRelationshipPermissions({
    required String relationshipId,
    required bool canViewWomenCalendar,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/care/relationships/$relationshipId/permissions',
      body: {'canViewWomenCalendar': canViewWomenCalendar},
    ),
  );

  Future<Map<String, dynamic>> updateCareNotificationPreferences({
    required String relationshipId,
    required bool enabled,
    required bool missedAlertsEnabled,
    required String completionMode,
    required bool careEventsEnabled,
    required bool dailySummaryEnabled,
    required String dailySummaryLocalTime,
    required String lockScreenDetail,
  }) async => _asObject(
    await _send(
      'PATCH',
      '/api/v1/care/relationships/$relationshipId/permissions',
      body: {
        'notificationPreferences': {
          'enabled': enabled,
          'missedAlertsEnabled': missedAlertsEnabled,
          'completionMode': completionMode.trim().toLowerCase(),
          'careEventsEnabled': careEventsEnabled,
          'dailySummaryEnabled': dailySummaryEnabled,
          'dailySummaryLocalTime': dailySummaryLocalTime.trim(),
          'lockScreenDetail': lockScreenDetail.trim().toLowerCase(),
        },
      },
    ),
  );

  Future<List<Map<String, dynamic>>> claimCareCompletionNotifications({
    required String relationshipId,
  }) async {
    final value = _asObject(
      await _send(
        'PATCH',
        '/api/v1/care/relationships/$relationshipId/permissions',
        body: {'claimCompletionNotifications': true},
      ),
    );
    final items = value['completionNotifications'];
    if (items is! List) return const <Map<String, dynamic>>[];
    return items.map(_asObject).toList(growable: false);
  }

  Future<Map<String, dynamic>> getCareRecipientWomenCalendar({
    required String patientUserId,
  }) async => _asObject(
    await _send(
      'GET',
      '/api/v1/care/patients/$patientUserId/women-calendar',
      retryable: true,
    ),
  );

  Future<Map<String, dynamic>> recordCareRecipientWomenSupportAction({
    required String patientUserId,
    required String actionType,
  }) async => _asObject(
    await _send(
      'POST',
      '/api/v1/care/patients/$patientUserId/women-calendar/support-actions',
      body: {'actionType': actionType.trim().toLowerCase()},
    ),
  );

  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, String>? query,
  }) async {
    final value = await _send('GET', path, query: query, retryable: true);
    if (value is! List) {
      throw const FormatException('LifeMate API returned a non-list payload.');
    }
    return value.map(_asObject).toList(growable: false);
  }

  Future<dynamic> _sendBinary(
    String method,
    String path, {
    required Uint8List bytes,
    required String contentType,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }
    if (method != 'PUT') {
      throw ArgumentError.value(method, 'method', 'Unsupported binary method');
    }
    try {
      final response = await _http
          .put(
            _resolve(path),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
              'Content-Type': contentType,
              ...headers,
            },
            body: bytes,
          )
          .timeout(_requestTimeout);
      return _decodeResponse(response);
    } on TimeoutException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_timeout',
        message: 'LifeMate request timed out.',
      );
    } on http.ClientException {
      throw const LifeMateApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'LifeMate service is unavailable.',
      );
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool retryable = false,
    String? idempotencyKey,
  }) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const LifeMateApiException(
        statusCode: 401,
        code: 'session_missing',
        message: 'Authentication session is missing.',
      );
    }

    var uri = _resolve(path);
    if (query != null) uri = uri.replace(queryParameters: query);
    final encodedBody = body == null ? null : jsonEncode(body);
    final isMutation =
        method == 'POST' ||
        method == 'PUT' ||
        method == 'PATCH' ||
        method == 'DELETE';
    final mutationFingerprint = isMutation
        ? '$method ${uri.toString()}\n${encodedBody ?? ''}'
        : null;
    final generatedMutationKey = isMutation && idempotencyKey == null;
    final mutationKey = !isMutation
        ? null
        : idempotencyKey ??
              _pendingMutationKeys.putIfAbsent(
                mutationFingerprint!,
                LifeMateApiClient.createClientRequestId,
              );
    final headers = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      if (body != null) 'Content-Type': 'application/json',
      if (mutationKey != null) 'Idempotency-Key': mutationKey,
    };
    final maxAttempts = retryable || isMutation ? 3 : 1;
    final budget = Stopwatch()..start();

    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      final remainingMilliseconds =
          _retryBudget.inMilliseconds - budget.elapsedMilliseconds;
      if (remainingMilliseconds <= 0) {
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'retry_budget_exhausted',
          message: 'LifeMate retry budget was exhausted.',
        );
      }
      final attemptTimeout = Duration(
        milliseconds: min(
          _requestTimeout.inMilliseconds,
          remainingMilliseconds,
        ),
      );

      late final http.Response response;
      try {
        response = await _sendOnce(
          method: method,
          uri: uri,
          headers: headers,
          encodedBody: encodedBody,
        ).timeout(attemptTimeout);
      } on TimeoutException {
        if (attempt < maxAttempts && await _waitBeforeRetry(attempt, budget)) {
          continue;
        }
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_timeout',
          message: 'LifeMate request timed out.',
        );
      } on http.ClientException {
        if (attempt < maxAttempts && await _waitBeforeRetry(attempt, budget)) {
          continue;
        }
        throw const LifeMateApiException(
          statusCode: 0,
          code: 'network_unavailable',
          message: 'LifeMate service is unavailable.',
        );
      }

      final retryResponse = _shouldRetryResponse(response);
      if (attempt < maxAttempts &&
          retryResponse &&
          await _waitBeforeRetry(attempt, budget, response: response)) {
        continue;
      }

      try {
        final decoded = _decodeResponse(response);
        if (generatedMutationKey) {
          _pendingMutationKeys.remove(mutationFingerprint);
        }
        return decoded;
      } on LifeMateApiException {
        if (generatedMutationKey && !retryResponse) {
          _pendingMutationKeys.remove(mutationFingerprint);
        }
        rethrow;
      }
    }

    throw StateError('LifeMate retry loop exited unexpectedly.');
  }

  Future<bool> _waitBeforeRetry(
    int attempt,
    Stopwatch budget, {
    http.Response? response,
  }) async {
    var delay = _retryDelayForAttempt(attempt);
    final retryAfter = response == null
        ? null
        : int.tryParse(response.headers['retry-after'] ?? '');
    if (retryAfter != null && retryAfter > 0) {
      final serverDelay = Duration(seconds: retryAfter);
      if (serverDelay > delay) delay = serverDelay;
    }
    if (budget.elapsedMilliseconds + delay.inMilliseconds >=
        _retryBudget.inMilliseconds) {
      return false;
    }
    await Future<void>.delayed(delay);
    return true;
  }

  Duration _retryDelayForAttempt(int attempt) {
    final exponent = 1 << (attempt - 1);
    final exponential = _retryBaseDelay.inMilliseconds * exponent;
    final jitter = _retryRandom.nextInt(_retryBaseDelay.inMilliseconds + 1);
    return Duration(
      milliseconds: min(_retryMaxDelay.inMilliseconds, exponential + jitter),
    );
  }

  bool _shouldRetryResponse(http.Response response) {
    if (_transientStatusCodes.contains(response.statusCode)) return true;
    if (response.statusCode != 409 || response.body.isEmpty) return false;
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> &&
          decoded['code']?.toString() == 'idempotency_in_progress';
    } on FormatException {
      return false;
    }
  }

  Future<http.Response> _sendOnce({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String? encodedBody,
  }) {
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'POST':
        return _http.post(uri, headers: headers, body: encodedBody);
      case 'PUT':
        return _http.put(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return _http.delete(uri, headers: headers);
      default:
        throw ArgumentError.value(method, 'method', 'Unsupported HTTP method');
    }
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const FormatException(
            'LifeMate API returned an invalid JSON payload.',
          );
        }
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final problem = decoded is Map<String, dynamic> ? decoded : const {};
    throw LifeMateApiException(
      statusCode: response.statusCode,
      code: (problem['code'] ?? problem['title'] ?? 'request_failed')
          .toString(),
      message: (problem['detail'] ?? 'LifeMate request failed.').toString(),
    );
  }

  static Map<String, dynamic> _asObject(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('LifeMate API returned a non-object payload.');
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Uri _resolve(String path) {
    final base = _baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final relative = path.replaceFirst(RegExp(r'^/+'), '');
    return Uri.parse('$base/$relative');
  }

  static String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void close() {
    _pendingMutationKeys.clear();
    _http.close();
  }
}
