import 'package:lifemate_core/lifemate_core.dart';

export 'offline_namespace_local_extension.dart';

import 'incremental_projection_api.dart';
import 'lifemate_api_client.dart';
import 'shared_offline_runtime.dart';

/// Low-cardinality result for one bounded owner care-event pull cycle.
/// It intentionally contains counts/cursor state only, never PHI or record IDs.
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

/// Connects the owner-only lifemate-api pull contract to the shared encrypted
/// #829/#831 projection reconciler. This is orchestration only: it does not own
/// another database, outbox, cursor store or reminder scheduler.
final class LifeMateCareEventProjectionSync {
  LifeMateCareEventProjectionSync({
    required LifeMateSharedOfflineRuntime runtime,
    required LifeMateIncrementalProjectionApi api,
  }) : _runtime = runtime,
       _api = api;

  final LifeMateSharedOfflineRuntime _runtime;
  final LifeMateIncrementalProjectionApi _api;

  /// Pulls at most [maximumPages] pages. Every page is checkpointed only after
  /// [beforeCheckpoint] succeeds, allowing affected #830 reminder regeneration
  /// to participate in the same replay-safe acknowledgement boundary.
  Future<LifeMateCareEventProjectionSyncResult> sync({
    int pageSize = 100,
    int maximumPages = 10,
    LifeMateBeforeProjectionCheckpoint? beforeCheckpoint,
  }) async {
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Must be 1..200.');
    }
    if (maximumPages < 1 || maximumPages > 100) {
      throw ArgumentError.value(
        maximumPages,
        'maximumPages',
        'Must be 1..100.',
      );
    }

    var cursor = (await _runtime.careEventCheckpoint())?.cursor;
    var pages = 0;
    var applied = 0;
    var deleted = 0;
    var hasMore = false;

    do {
      final page = await _api.pullCareEvents(cursor: cursor, limit: pageSize);
      if (page.nextCursor == cursor && page.hasMore) {
        throw const LifeMateApiException(
          statusCode: 502,
          code: 'invalid_api_response',
          message: 'The service returned a non-advancing sync cursor.',
        );
      }

      final reconciled = await _runtime.applyCareEventPage(
        page: page,
        beforeCheckpoint: beforeCheckpoint,
      );
      pages += 1;
      applied += reconciled.applied;
      deleted += reconciled.deleted;
      cursor = reconciled.nextCursor;
      hasMore = page.hasMore;
    } while (hasMore && pages < maximumPages);

    return LifeMateCareEventProjectionSyncResult(
      pages: pages,
      applied: applied,
      deleted: deleted,
      hasMore: hasMore,
    );
  }
}
