import 'cocoon_pregnancy.dart';

const int _dayMilliseconds = 86400000;
const int _termDays = 280;
const int _maxReferenceGestationalDays = 308;

/// Privacy-safe, machine-readable failure for deterministic local pregnancy
/// dating. Codes intentionally contain no reproductive dates or identifiers.
final class CocoonPregnancyDatingError implements Exception {
  const CocoonPregnancyDatingError(this.code);

  final String code;

  @override
  String toString() => 'CocoonPregnancyDatingError($code)';
}

/// Mirrors the canonical v1 server dating contract for owner-only offline
/// presentation.
///
/// [asOfLocalDate] is already the user's local calendar date. Only its
/// year/month/day components are used; this function never infers a timezone.
/// This calculation is presentation state only and must not become a second
/// mutable pregnancy truth source.
CocoonGestationalAge? deriveCocoonGestationalAgeOffline({
  required CocoonPregnancyDating dating,
  required DateTime asOfLocalDate,
}) {
  final asOfOrdinal = _dateOrdinal(
    _formatLocalDate(asOfLocalDate),
    'as_of_date',
  );
  final method = dating.method;
  if (method == null) return null;

  switch (method) {
    case 'lmp':
      if (dating.lmpDate == null) {
        throw const CocoonPregnancyDatingError('lmp_date_required');
      }
      return _deriveFromLmp(dating, asOfOrdinal);
    case 'edd':
      if (dating.estimatedDueDate == null) {
        throw const CocoonPregnancyDatingError('estimated_due_date_required');
      }
      return _deriveFromEdd(dating, asOfOrdinal);
    case 'clinician_ultrasound':
      if (dating.referenceDate == null ||
          dating.gestationalAgeAtReferenceDays == null) {
        throw const CocoonPregnancyDatingError(
          'clinician_reference_required',
        );
      }
      return _deriveFromReference(dating, asOfOrdinal);
    case 'manual_correction':
    case 'imported':
      return _deriveFromReference(dating, asOfOrdinal) ??
          _deriveFromEdd(dating, asOfOrdinal) ??
          _deriveFromLmp(dating, asOfOrdinal);
    default:
      // A future server dating method is not safe to reinterpret locally.
      return null;
  }
}

CocoonGestationalAge? _deriveFromReference(
  CocoonPregnancyDating dating,
  int asOfOrdinal,
) {
  final referenceDate = dating.referenceDate;
  if (referenceDate == null) return null;
  final referenceOrdinal = _dateOrdinal(referenceDate, 'reference_date');
  final referenceDays = _requireReferenceDays(
    dating.gestationalAgeAtReferenceDays,
  );
  return _normalizeGestationalDays(
    referenceDays + (asOfOrdinal - referenceOrdinal),
    'reference',
  );
}

CocoonGestationalAge? _deriveFromEdd(
  CocoonPregnancyDating dating,
  int asOfOrdinal,
) {
  final estimatedDueDate = dating.estimatedDueDate;
  if (estimatedDueDate == null) return null;
  final eddOrdinal = _dateOrdinal(estimatedDueDate, 'estimated_due_date');
  return _normalizeGestationalDays(
    _termDays - (eddOrdinal - asOfOrdinal),
    'edd',
  );
}

CocoonGestationalAge? _deriveFromLmp(
  CocoonPregnancyDating dating,
  int asOfOrdinal,
) {
  final lmpDate = dating.lmpDate;
  if (lmpDate == null) return null;
  final lmpOrdinal = _dateOrdinal(lmpDate, 'lmp_date');
  return _normalizeGestationalDays(asOfOrdinal - lmpOrdinal, 'lmp');
}

CocoonGestationalAge? _normalizeGestationalDays(
  int totalDays,
  String basis,
) {
  if (totalDays < 0) return null;
  return CocoonGestationalAge(
    totalDays: totalDays,
    week: totalDays ~/ 7,
    day: totalDays % 7,
    basis: basis,
  );
}

int _requireReferenceDays(int? value) {
  if (value == null || value < 0 || value > _maxReferenceGestationalDays) {
    throw const CocoonPregnancyDatingError(
      'gestational_age_at_reference_invalid',
    );
  }
  return value;
}

int _dateOrdinal(String value, String field) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw CocoonPregnancyDatingError('${field}_invalid');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw CocoonPregnancyDatingError('${field}_invalid');
  }
  return date.millisecondsSinceEpoch ~/ _dayMilliseconds;
}

String _formatLocalDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
