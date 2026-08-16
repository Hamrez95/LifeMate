import 'offline_sync_result.dart';

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
      return const LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.refreshRequired,
        titleFa: 'اطلاعات به‌روز شد',
        titleEn: 'Refresh required',
        messageFa:
            'یک تغییر قدیمی با وضعیت فعلی هماهنگ نبود. صفحه را تازه کنید تا وضعیت قطعی سرور نمایش داده شود.',
        messageEn:
            'An older change no longer matched the current state. Refresh to show the authoritative server state.',
      );
    }
    if (result.retainedForRetry > 0 || result.hasPending) {
      return const LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.retryPending,
        titleFa: 'همگام‌سازی ادامه دارد',
        titleEn: 'Sync still pending',
        messageFa:
            'تغییر ذخیره شده و پس از پایدار شدن اتصال دوباره با همان درخواست امن تلاش می‌شود.',
        messageEn:
            'The change remains safely queued and will retry with the same idempotent request when the connection is stable.',
      );
    }
    if (result.replayed > 0) {
      return const LifeMateOfflineSyncFeedback(
        kind: LifeMateOfflineFeedbackKind.replayed,
        titleFa: 'همگام‌سازی انجام شد',
        titleEn: 'Sync completed',
        messageFa: 'تغییر ذخیره‌شده بدون ایجاد عملیات تکراری همگام شد.',
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
