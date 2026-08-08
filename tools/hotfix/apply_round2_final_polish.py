from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}: {old[:100]!r}')
    write(path, text.replace(old, new, 1))


replace_once(
    'wellmate/lib/screens/treatments/edit_care_event_screen.dart',
    '''      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _isAppointment
                ? 'تغییرات ویزیت ذخیره شد.'
                : 'تغییرات تزریق ذخیره شد.',
          ),
        ),
      );''',
    '''      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: _isAppointment ? 'ویزیت به‌روزرسانی شد' : 'تزریق به‌روزرسانی شد',
        message: 'تغییرات با موفقیت ذخیره شد.',
      );''',
)

replace_once(
    'wellmate/lib/screens/treatments/edit_treatment_screen.dart',
    '''      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تغییرات درمان با موفقیت ذخیره شد.'),
        ),
      );''',
    '''      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: 'درمان به‌روزرسانی شد',
        message: 'تغییرات درمان با موفقیت ذخیره شد.',
      );''',
)

write(
    'wellmate/test/home_injection_timeline_test.dart',
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:wellmate/screens/home/home_schedule_loader.dart';

void main() {
  test('injection appears in aggregate daily timeline snapshot', () async {
    const loader = HomeScheduleLoader();
    final snapshot = await loader.load(
      api: _InjectionSnapshotApi(),
      fromDate: DateTime(2026, 8, 17),
      toDate: DateTime(2026, 8, 17),
    );

    expect(
      snapshot.careEvents.any(
        (event) =>
            event['eventType'] == 'injection' && event['title'] == 'B12',
      ),
      isTrue,
    );
  });
}

class _InjectionSnapshotApi extends LifeMateApiClient {
  _InjectionSnapshotApi()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  @override
  Future<Map<String, dynamic>> getHomeSnapshot({
    required DateTime fromDate,
    required DateTime toDate,
  }) async => const {
        'currentUser': {
          'profile': {'displayName': 'ریحانه', 'timeZone': 'Asia/Tehran'},
        },
        'treatmentPlans': <Map<String, dynamic>>[],
        'doseOccurrences': <Map<String, dynamic>>[],
        'careEvents': [
          {
            'id': 'inj-1:2026-08-17',
            'seriesId': 'inj-1',
            'eventType': 'injection',
            'title': 'B12',
            'doseText': '۱ آمپول',
            'centerName': 'درمانگاه',
            'scheduledLocalDate': '2026-08-17',
            'scheduledLocalTime': '21:30',
            'status': 'scheduled',
          },
        ],
      };
}
''',
)

write(
    'wellmate/test/calendar_care_color_tokens_test.dart',
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/screens/calendar/calendar_utils.dart';

void main() {
  test('calendar uses semantic care item color tokens', () {
    expect(CalendarUtils.getColorForType('med'), AppColors.careMedication);
    expect(CalendarUtils.getColorForType('appointment'), AppColors.careVisit);
    expect(CalendarUtils.getColorForType('injection'), AppColors.careInjection);
  });
}
''',
)

write(
    'wellmate/test/form_theme_regression_test.dart',
    r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared app form themes distinguish hint label and value hierarchy', () {
    for (final path in ['lib/main.dart', '../caremate/lib/main.dart']) {
      final source = File(path).readAsStringSync();
      expect(source, contains('hintStyle: const TextStyle('), reason: path);
      expect(source, contains('Color(0xFF8B95A3)'), reason: path);
      expect(source, contains('labelStyle: const TextStyle('), reason: path);
      expect(source, contains('Color(0xFF667085)'), reason: path);
      expect(source, contains('floatingLabelStyle:'), reason: path);
    }
  });
}
''',
)

Path(__file__).unlink()
workflow = ROOT / '.github/workflows/round2-final-polish-one-shot.yml'
if workflow.exists():
    workflow.unlink()
print('round2 final polish applied')
