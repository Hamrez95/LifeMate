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
    required this.titleFa,
    required this.titleEn,
    required this.messageFa,
    required this.messageEn,
  });

  factory LifeMateOfflineSyncFeedback.fromResult(
    LifeMateOfflineSyncResult result,
  ) {
    if (result.needsRefresh) {
      return LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.refreshRequired,
        titleFa: LifeMateRuntimeLocale.select(
          fa: 'اطلاعات به‌روز شد',
          en: 'Refresh required',
        ),
        titleEn: 'Refresh required',
        messageFa: LifeMateRuntimeLocale.select(
          fa: 'یک تغییر قدیمی با وضعیت فعلی هماهنگ نبود. صفحه را تازه کنید تا وضعیت قطعی سرور نمایش داده شود.',
          en: 'An older change no longer matched the current state. Refresh to show the authoritative server state.',
        ),
        messageEn:
            'An older change no longer matched the current state. Refresh to show the authoritative server state.',
      );
    }
    if (result.retainedForRetry > 0 || result.hasPending) {
      return LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.retryPending,
        titleFa: LifeMateRuntimeLocale.select(
          fa: 'همگام‌سازی ادامه دارد',
          en: 'Sync still pending',
        ),
        titleEn: 'Sync still pending',
        messageFa: LifeMateRuntimeLocale.select(
          fa: 'تغییر ذخیره شده و پس از پایدار شدن اتصال دوباره با همان درخواست امن تلاش می‌شود.',
          en: 'The change remains safely queued and will retry with the same idempotent request when the connection is stable.',
        ),
        messageEn:
            'The change remains safely queued and will retry with the same idempotent request when the connection is stable.',
      );
    }
    if (result.replayed > 0) {
      return LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.replayed,
        titleFa: LifeMateRuntimeLocale.select(
          fa: 'همگام‌سازی انجام شد',
          en: 'Sync completed',
        ),
        titleEn: 'Sync completed',
        messageFa: LifeMateRuntimeLocale.select(
          fa: 'تغییر ذخیره‌شده بدون ایجاد عملیات تکراری همگام شد.',
          en: 'The queued change synced without creating a duplicate operation.',
        ),
        messageEn:
            'The queued change synced without creating a duplicate operation.',
      );
    }
    return const LifeMateOfflineSyncFeedback(
      kind: LifeMateOfflineFeedbackKind.noChange,
      titleFa: '',
      titleEn: '',
      messageFa: '',
      messageEn: '',
    );
  }

  final LifeMateOfflineFeedbackKind kind;
  final String titleFa;
  final String titleEn;
  final String messageFa;
  final String messageEn;

  bool get shouldNotify => kind != LifeMateOfflineFeedbackKind.noChange;
  bool get shouldRefresh =>
      kind == LifeMateOfflineFeedbackKind.refreshRequired;
}
