import 'local_health_store.dart';
import 'local_mutation_outbox.dart';

/// Low-cardinality replay outcome. It deliberately contains no identifiers,
/// endpoint paths, payloads, server messages, or health values.
final class LifeMateMutationReplayResult {
  const LifeMateMutationReplayResult({
    this.confirmed = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.retainedForRetry = 0,
    this.remaining = 0,
  });

  final int confirmed;
  final int conflicts;
  final int rejected;
  final int retainedForRetry;
  final int remaining;
}

/// Minimal transport result consumed by the shared replay engine. Response
/// bodies are intentionally absent so API error text/PHI cannot leak into the
/// shared retry state or telemetry by accident.
final class LifeMateMutationReplayResponse {
  const LifeMateMutationReplayResponse(this.statusCode);

  final int statusCode;
}

/// Only expected connectivity failures should cross the transport boundary as
/// this type. Programmer/serialization/security failures must surface instead
/// of being silently converted into an infinite retry loop.
final class LifeMateMutationReplayTransportException implements Exception {
  const LifeMateMutationReplayTransportException();
}

abstract interface class LifeMateMutationReplayTransport {
  Future<LifeMateMutationReplayResponse> send(
    LifeMateDurableMutation mutation,
  );
}

/// Replays the #831 protected outbox without embedding product/network code in
/// lifemate_core. The engine owns deterministic HTTP-class semantics while the
/// adapter owns authenticated transport to lifemate-api.
///
/// Safety properties:
/// - mutations are processed serially in durable creation order;
/// - only a 2xx acknowledgement removes an accepted logical action;
/// - 409 remains durable as an explicit domain conflict (never silent LWW);
/// - auth/throttle/server/transport failures are retained with bounded backoff;
/// - a retryable failure stops the run to avoid battery/network retry storms;
/// - terminal 4xx responses are retained as explicit rejected state rather than
///   falsely represented as server-confirmed;
/// - unexpected implementation failures surface and leave the durable record
///   untouched.
final class LifeMateLocalMutationReplayEngine {
  LifeMateLocalMutationReplayEngine({
    required LifeMateLocalMutationOutbox outbox,
    required LifeMateMutationReplayTransport transport,
    this.maximumMutationsPerRun = 25,
    DateTime Function()? now,
  }) : _outbox = outbox,
       _transport = transport,
       _now = now ?? (() => DateTime.now().toUtc()) {
    if (maximumMutationsPerRun <= 0) {
      throw ArgumentError.value(
        maximumMutationsPerRun,
        'maximumMutationsPerRun',
      );
    }
  }

  final LifeMateLocalMutationOutbox _outbox;
  final LifeMateMutationReplayTransport _transport;
  final DateTime Function() _now;
  final int maximumMutationsPerRun;

  Future<LifeMateMutationReplayResult> replayEligible({
    required LifeMateLocalNamespace namespace,
  }) async {
    final now = _now().toUtc();
    final eligible = await _outbox.eligible(namespace: namespace, atUtc: now);

    var confirmed = 0;
    var conflicts = 0;
    var rejected = 0;
    var retainedForRetry = 0;

    final limit = eligible.length < maximumMutationsPerRun
        ? eligible.length
        : maximumMutationsPerRun;

    for (var index = 0; index < limit; index++) {
      final mutation = eligible[index];
      LifeMateMutationReplayResponse response;
      try {
        response = await _transport.send(mutation);
      } on LifeMateMutationReplayTransportException {
        await _outbox.markRetry(
          namespace: namespace,
          mutationId: mutation.mutationId,
          errorClass: LifeMateMutationErrorClass.transport,
        );
        retainedForRetry += 1;
        break;
      }

      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        final acknowledged = await _outbox.acknowledge(
          namespace: namespace,
          mutationId: mutation.mutationId,
        );
        if (acknowledged != null) confirmed += 1;
        continue;
      }

      if (status == 409) {
        await _outbox.markConflict(
          namespace: namespace,
          mutationId: mutation.mutationId,
        );
        conflicts += 1;
        continue;
      }

      final retryClass = _retryClassFor(status);
      if (retryClass != null) {
        await _outbox.markRetry(
          namespace: namespace,
          mutationId: mutation.mutationId,
          errorClass: retryClass,
        );
        retainedForRetry += 1;
        break;
      }

      if (status >= 400 && status < 500) {
        await _outbox.markRejected(
          namespace: namespace,
          mutationId: mutation.mutationId,
        );
        rejected += 1;
        continue;
      }

      // Non-HTTP/invalid adapter output is unsafe. Surface it rather than
      // mutating durable state based on an undefined transport contract.
      throw StateError('Replay transport returned an invalid status code.');
    }

    final all = await _outbox.list(namespace: namespace);
    final remaining = all
        .where(
          (mutation) =>
              mutation.state == LifeMateMutationSyncState.pending ||
              mutation.state == LifeMateMutationSyncState.retryScheduled,
        )
        .length;

    return LifeMateMutationReplayResult(
      confirmed: confirmed,
      conflicts: conflicts,
      rejected: rejected,
      retainedForRetry: retainedForRetry,
      remaining: remaining,
    );
  }

  static LifeMateMutationErrorClass? _retryClassFor(int status) {
    if (status == 401 || status == 403) {
      return LifeMateMutationErrorClass.authentication;
    }
    if (status == 408) return LifeMateMutationErrorClass.transport;
    if (status == 429) return LifeMateMutationErrorClass.throttled;
    if (status >= 500 && status < 600) {
      return LifeMateMutationErrorClass.server;
    }
    return null;
  }
}
