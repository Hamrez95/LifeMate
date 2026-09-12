/// Truthful presentation state for Cocoon host adapters.
///
/// These values describe what the host actually knows about the data. A queued
/// mutation must never be presented as server-confirmed and cached data remains
/// explicitly distinguishable while the network is unavailable.
enum CocoonAdapterState {
  loading,
  serverConfirmed,
  offlineCached,
  pendingSync,
  error,
}

class CocoonAdapterSnapshot<T> {
  const CocoonAdapterSnapshot({
    required this.state,
    this.value,
    this.errorCode,
  });

  const CocoonAdapterSnapshot.loading()
      : state = CocoonAdapterState.loading,
        value = null,
        errorCode = null;

  const CocoonAdapterSnapshot.confirmed(T data)
      : state = CocoonAdapterState.serverConfirmed,
        value = data,
        errorCode = null;

  const CocoonAdapterSnapshot.offlineCached(T data)
      : state = CocoonAdapterState.offlineCached,
        value = data,
        errorCode = null;

  const CocoonAdapterSnapshot.pendingSync(T data)
      : state = CocoonAdapterState.pendingSync,
        value = data,
        errorCode = null;

  const CocoonAdapterSnapshot.error(String code)
      : state = CocoonAdapterState.error,
        value = null,
        errorCode = code;

  final CocoonAdapterState state;
  final T? value;
  final String? errorCode;

  bool get isServerConfirmed => state == CocoonAdapterState.serverConfirmed;
  bool get isOffline => state == CocoonAdapterState.offlineCached;
  bool get isPendingSync => state == CocoonAdapterState.pendingSync;
}
