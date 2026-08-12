import 'runtime_locale.dart';

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
    if (minutes <= 0)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'در زمان برنامه',
          en: "During the program",
        ),
        en: "During the program",
      );
    if (minutes < 60)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '$minutes دقیقه قبل',
          en: "$minutes minutes ago",
        ),
        en: "$minutes minutes ago",
      );
    if (minutes == 60)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: '۱ ساعت قبل', en: "1 hour ago"),
        en: "1 hour ago",
      );
    if (minutes < 1440 && minutes % 60 == 0) {
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${minutes ~/ 60} ساعت قبل',
          en: "${minutes ~/ 60} hours ago",
        ),
        en: "${minutes ~/ 60} hours ago",
      );
    }
    if (minutes == 1440)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: '۱ روز قبل', en: "1 day ago"),
        en: "1 day ago",
      );
    if (minutes % 1440 == 0)
      return LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '${minutes ~/ 1440} روز قبل',
          en: "${minutes ~/ 1440} the day before",
        ),
        en: "${minutes ~/ 1440} the day before",
      );
    return LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: '$minutes دقیقه قبل',
        en: "$minutes minutes ago",
      ),
      en: "$minutes minutes ago",
    );
  }
}
