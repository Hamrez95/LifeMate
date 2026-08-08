abstract final class LifeMateReminderLeadTimes {
  static const int minimumMinutes = 0;
  static const int maximumMinutes = 10080;
  static const int defaultPatientMinutes = 30;
  static const int defaultCaregiverMinutes = 60;

  static const List<int> presets = <int>[0, 5, 10, 15, 30, 60, 120, 1440];

  static int normalize(Object? value, {required int fallback}) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < minimumMinutes || parsed > maximumMinutes) {
      return fallback;
    }
    return parsed;
  }

  static String label(int minutes) {
    if (minutes <= 0) return 'در زمان برنامه';
    if (minutes < 60) return '$minutes دقیقه قبل';
    if (minutes == 60) return '۱ ساعت قبل';
    if (minutes < 1440 && minutes % 60 == 0) {
      return '${minutes ~/ 60} ساعت قبل';
    }
    if (minutes == 1440) return '۱ روز قبل';
    if (minutes % 1440 == 0) return '${minutes ~/ 1440} روز قبل';
    return '$minutes دقیقه قبل';
  }
}
