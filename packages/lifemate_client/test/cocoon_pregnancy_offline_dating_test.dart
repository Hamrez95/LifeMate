import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  CocoonPregnancyDating dating({
    String? method,
    String? lmpDate,
    String? estimatedDueDate,
    String? referenceDate,
    int? referenceDays,
  }) => CocoonPregnancyDating(
    method: method,
    lmpDate: lmpDate,
    estimatedDueDate: estimatedDueDate,
    referenceDate: referenceDate,
    gestationalAgeAtReferenceDays: referenceDays,
    gestationalAge: null,
  );

  test('local LMP calculation matches canonical server fixture', () {
    final result = deriveCocoonGestationalAgeOffline(
      dating: dating(method: 'lmp', lmpDate: '2026-01-01'),
      asOfLocalDate: DateTime(2026, 1, 15),
    );
    expect(result?.totalDays, 14);
    expect(result?.week, 2);
    expect(result?.day, 0);
    expect(result?.basis, 'lmp');
  });

  test('local EDD calculation is 40w0d on due date', () {
    final result = deriveCocoonGestationalAgeOffline(
      dating: dating(method: 'edd', estimatedDueDate: '2026-10-08'),
      asOfLocalDate: DateTime(2026, 10, 8),
    );
    expect(result?.totalDays, 280);
    expect(result?.week, 40);
    expect(result?.day, 0);
    expect(result?.basis, 'edd');
  });

  test('clinician reference calculation matches server fixture', () {
    final result = deriveCocoonGestationalAgeOffline(
      dating: dating(
        method: 'clinician_ultrasound',
        referenceDate: '2026-06-01',
        referenceDays: 84,
      ),
      asOfLocalDate: DateTime(2026, 6, 8),
    );
    expect(result?.totalDays, 91);
    expect(result?.week, 13);
    expect(result?.day, 0);
    expect(result?.basis, 'reference');
  });

  test('manual correction prefers reference over EDD and LMP', () {
    final result = deriveCocoonGestationalAgeOffline(
      dating: dating(
        method: 'manual_correction',
        lmpDate: '2026-01-01',
        estimatedDueDate: '2026-10-08',
        referenceDate: '2026-06-01',
        referenceDays: 100,
      ),
      asOfLocalDate: DateTime(2026, 6, 2),
    );
    expect(result?.basis, 'reference');
    expect(result?.totalDays, 101);
  });

  test('unknown method is not interpreted locally', () {
    expect(
      deriveCocoonGestationalAgeOffline(
        dating: dating(method: 'future_contract_v2', lmpDate: '2026-01-01'),
        asOfLocalDate: DateTime(2026, 9, 3),
      ),
      isNull,
    );
  });

  test('date before known basis returns no gestational age', () {
    expect(
      deriveCocoonGestationalAgeOffline(
        dating: dating(method: 'lmp', lmpDate: '2026-09-10'),
        asOfLocalDate: DateTime(2026, 9, 3),
      ),
      isNull,
    );
  });

  test('invalid calendar input returns stable safe error code', () {
    expect(
      () => deriveCocoonGestationalAgeOffline(
        dating: dating(method: 'lmp', lmpDate: '2026-02-30'),
        asOfLocalDate: DateTime(2026, 9, 3),
      ),
      throwsA(
        isA<CocoonPregnancyDatingError>().having(
          (error) => error.code,
          'code',
          'lmp_date_invalid',
        ),
      ),
    );
  });

  test('local calendar boundary advances exactly one day', () {
    final input = dating(method: 'lmp', lmpDate: '2026-01-01');
    final before = deriveCocoonGestationalAgeOffline(
      dating: input,
      asOfLocalDate: DateTime(2026, 1, 7, 23, 59),
    );
    final after = deriveCocoonGestationalAgeOffline(
      dating: input,
      asOfLocalDate: DateTime(2026, 1, 8, 0, 1),
    );
    expect(before?.totalDays, 6);
    expect(after?.totalDays, 7);
    expect(after?.week, 1);
    expect(after?.day, 0);
  });
}
