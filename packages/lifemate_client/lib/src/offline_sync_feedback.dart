import 'offline_sync_result.dart';
import 'runtime_locale.dart';

enum LifeMateOfflineFeedbackKind {
  noChange,
  replayed,
  refreshRequired,
  retryPending,
}

class LifeMateOfflineSyncFeedback {
  const LifeMateOfflineSyncFeedback({
    required this.kind,
    required this.title,
    required this.message,
  });

  factory LifeMateOfflineSyncFeedback.fromResult(
    LifeMateOfflineSyncResult result,
  ) {
    if (result.needsRefresh) {
      return LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.refreshRequired,
        title: LifeMateRuntimeLocale.select(
          fa: 'اطلاعات به‌روز شد',
          en: 'Refresh required',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'یک تغییر قدیمی با وضعیت فعلی هماهنگ نبود. صفحه را تازه کنید تا وضعیت قطعی سرور نمایش داده شود.',
          en: 'An older change no longer matched the current state. Refresh to show the authoritative server state.',
        ),
      );
    }
    if (result.retainedForRetry > 0 || result.hasPending) {
      return LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.retryPending,
        title: LifeMateRuntimeLocale.select(
          fa: 'همگام‌سازی ادامه دارد',
          en: 'Sync still pending',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'تغییر ذخیره شده و پس از پایدار شدن اتصال دوباره با همان درخواست امن تلاش می‌شود.',
          en: 'The change remains safely queued and will retry with the same idempotent request when the connection is stable.',
        ),
      );
    }
    if (result.replayed > 0) {
      return LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.replayed,
        title: LifeMateRuntimeLocale.select(
          fa: 'همگام‌سازی انجام شد',
          en: 'Sync completed',
        ),
        message: LifeMateRuntimeLocale.select(
          fa: 'تغییر ذخیره‌شده بدون ایجاد عملیات تکراری همگام شد.',
          en: 'The queued change synced without creating a duplicate operation.',
        ),
      );
    }
    return const LifeMateOfflineSyncFeedback(
      kind: LifeMateOfflineFeedbackKind.noChange,
      title: '',
      message: '',
    );
  }

  final LifeMateOfflineFeedbackKind kind;
  final String title;
  final String message;

  bool get shouldNotify => kind != LifeMateOfflineFeedbackKind.noChange;
  bool get shouldRefresh =>
      kind == LifeMateOfflineFeedbackKind.refreshRequired;
}
