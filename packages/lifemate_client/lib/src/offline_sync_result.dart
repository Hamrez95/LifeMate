class LifeMateOfflineSyncResult {
  const LifeMateOfflineSyncResult({
    this.replayed = 0,
    this.conflicts = 0,
    this.terminalRejected = 0,
    this.retainedForRetry = 0,
    this.removedUnsafe = 0,
    this.pendingRemaining = 0,
  });

  final int replayed;
  final int conflicts;
  final int terminalRejected;
  final int retainedForRetry;
  final int removedUnsafe;
  final int pendingRemaining;

  int get synced => replayed;
  bool get needsRefresh => conflicts > 0 || terminalRejected > 0;
  bool get hasPending => pendingRemaining > 0;

  Map<String, Object> toJson() => <String, Object>{
        'replayed': replayed,
        'conflicts': conflicts,
        'terminalRejected': terminalRejected,
        'retainedForRetry': retainedForRetry,
        'removedUnsafe': removedUnsafe,
        'pendingRemaining': pendingRemaining,
        'needsRefresh': needsRefresh,
      };
}
