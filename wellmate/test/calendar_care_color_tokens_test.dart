import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/screens/calendar/calendar_utils.dart';

void main() {
  test('calendar uses distinct semantic care item color tokens', () {
    expect(CalendarUtils.getColorForType('med'), AppColors.careMedication);
    expect(CalendarUtils.getColorForType('appointment'), AppColors.careVisit);
    expect(CalendarUtils.getColorForType('injection'), AppColors.careInjection);
    expect(CalendarUtils.getColorForType('treatment'), AppColors.careInjection);
    expect(AppColors.careInjection, isNot(AppColors.careVisit));
    expect(AppColors.careInjection, isNot(AppColors.careMedication));
  });
}
