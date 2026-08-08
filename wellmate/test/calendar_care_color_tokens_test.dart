import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/screens/calendar/calendar_utils.dart';

void main() {
  test('calendar uses semantic care item color tokens', () {
    expect(CalendarUtils.getColorForType('med'), AppColors.careMedication);
    expect(CalendarUtils.getColorForType('appointment'), AppColors.careVisit);
    expect(CalendarUtils.getColorForType('injection'), AppColors.careInjection);
  });
}
