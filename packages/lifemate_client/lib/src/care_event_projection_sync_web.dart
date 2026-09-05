import 'package:lifemate_core/lifemate_core.dart';

/// Web keeps the projection API surface available for shared UI code, but does
/// not create a browser health store or acknowledge durable projection cursors.
final class LifeMateCareEventProjectionSyncResult {
  const LifeMateCareEventProjectionSyncResult({
    required this.pages,
    required this.applied,
    required this.deleted,
    required this.hasMore,
  });

  final int pages;
  final int applied;
  final int deleted;
  final bool hasMore;
}

final class LifeMateCareEventProjectionSync {
  LifeMateCareEventProjectionSync({required Object runtime, required Object api});

  Future<LifeMateCareEventProjectionSyncResult> sync({
    int pageSize = 100,
    int maximumPages = 10,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) => Future<LifeMateCareEventProjectionSyncResult>.error(
    UnsupportedError('Protected offline health execution is unavailable on web.'),
  );
}
