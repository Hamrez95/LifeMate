/// Platform-neutral pre-checkpoint view exposed to product reminder adapters.
///
/// The durable native projection engine may keep richer encrypted-store state,
/// but product code only needs the affected server record keys before the
/// cursor is acknowledged. Keeping this contract free of SQLite/FFI lets web
/// builds remain online-only without importing the native health store.
final class LifeMateProjectionCheckpointStage {
  LifeMateProjectionCheckpointStage({required Iterable<String> affectedRecordKeys})
      : affectedRecordKeys = Set<String>.unmodifiable(affectedRecordKeys);

  final Set<String> affectedRecordKeys;
}

typedef LifeMateBeforeProjectionCheckpoint =
    Future<void> Function(LifeMateProjectionCheckpointStage stagedResult);
