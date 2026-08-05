import 'women_calendar.dart';

extension NullableWomenCalendarEstimateProjection on WomenCalendarEstimate? {
  int get daysUntilNextPeriod => this?.daysUntilNextPeriod ?? 0;
}
