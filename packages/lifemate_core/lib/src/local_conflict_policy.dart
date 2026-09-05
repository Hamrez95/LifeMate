/// Deterministic per-domain conflict semantics for LifeMate offline replay.
///
/// This layer deliberately does not mutate local/server state. It classifies a
/// canonical reconciliation situation so product adapters can apply one shared,
/// reviewable policy instead of falling back to global last-write-wins.
library;

enum LifeMateConflictDomain {
  adherence,
  treatment,
  careEvent,
  womenHealthCycle,
  pregnancyDating,
  observation,
  sharedAuthorization,
}

enum LifeMateConflictDisposition {
  /// The server already represents the same logical user action. The pending
  /// local mutation can be acknowledged without creating a second event.
  acknowledgeEquivalent,

  /// No conflicting canonical change is known. Normal replay may continue.
  replayAllowed,

  /// Refresh canonical state before retrying the local mutation.
  refreshThenRetry,

  /// A deterministic domain merge/dedupe adapter must run before acknowledgement.
  deterministicMergeRequired,

  /// User/domain-specific resolution is required. Never silently overwrite.
  explicitResolutionRequired,

  /// Authoritative shared access is gone. Cached shared data/access must fail
  /// closed and must not be used to continue another Person's authorization.
  invalidateSharedAccess,
}

final class LifeMateConflictContext {
  const LifeMateConflictContext({
    required this.domain,
    this.sameLogicalEvent = false,
    this.sameCanonicalValue = false,
    this.expectedRevision,
    this.serverRevision,
    this.overlappingFact = false,
    this.authoritativeAccessRevoked = false,
  });

  final LifeMateConflictDomain domain;

  /// True only when stable idempotency/logical identity proves both sides refer
  /// to the same logical action or fact. Payload similarity alone is not enough.
  final bool sameLogicalEvent;

  /// True when canonical semantic value is equivalent after domain normalization
  /// (for example an already-confirmed Taken event with the same logical ID).
  final bool sameCanonicalValue;

  /// Expected source revision captured when the local edit was accepted.
  final String? expectedRevision;

  /// Current authoritative source revision after refresh/conflict response.
  final String? serverRevision;

  /// Domain-level overlap that is not proven to be the same logical fact.
  final bool overlappingFact;

  /// Set only from authoritative access/consent refresh, never from stale cache.
  final bool authoritativeAccessRevoked;

  bool get revisionChanged {
    final expected = expectedRevision?.trim();
    final server = serverRevision?.trim();
    return expected != null &&
        expected.isNotEmpty &&
        server != null &&
        server.isNotEmpty &&
        expected != server;
  }
}

abstract final class LifeMateConflictPolicy {
  static const int policyVersion = 1;

  static LifeMateConflictDisposition resolve(LifeMateConflictContext context) {
    if (context.domain == LifeMateConflictDomain.sharedAuthorization &&
        context.authoritativeAccessRevoked) {
      return LifeMateConflictDisposition.invalidateSharedAccess;
    }

    if (context.sameLogicalEvent && context.sameCanonicalValue) {
      return LifeMateConflictDisposition.acknowledgeEquivalent;
    }

    return switch (context.domain) {
      LifeMateConflictDomain.adherence => _resolveAdherence(context),
      LifeMateConflictDomain.treatment => _resolveVersionedEdit(context),
      LifeMateConflictDomain.careEvent => _resolveVersionedEdit(context),
      LifeMateConflictDomain.womenHealthCycle => _resolveWomenCycle(context),
      LifeMateConflictDomain.pregnancyDating => _resolvePregnancyDating(
        context,
      ),
      LifeMateConflictDomain.observation => _resolveObservation(context),
      LifeMateConflictDomain.sharedAuthorization => _resolveSharedAuthorization(
        context,
      ),
    };
  }

  static LifeMateConflictDisposition _resolveAdherence(
    LifeMateConflictContext context,
  ) {
    // Taken/Skipped/Later is an idempotent logical occurrence action. If a
    // canonical value already exists for the same occurrence but is not proven
    // equivalent, silently replacing it could rewrite adherence history.
    if (context.sameLogicalEvent) {
      return LifeMateConflictDisposition.explicitResolutionRequired;
    }
    return LifeMateConflictDisposition.refreshThenRetry;
  }

  static LifeMateConflictDisposition _resolveVersionedEdit(
    LifeMateConflictContext context,
  ) {
    if (context.revisionChanged) {
      return LifeMateConflictDisposition.explicitResolutionRequired;
    }
    return LifeMateConflictDisposition.replayAllowed;
  }

  static LifeMateConflictDisposition _resolveWomenCycle(
    LifeMateConflictContext context,
  ) {
    // Exact logical duplicates are handled by the equivalent fast path above.
    // Overlapping period/cycle facts require the versioned deterministic merge
    // adapter; they must never become generic last-write-wins updates.
    if (context.overlappingFact || context.revisionChanged) {
      return LifeMateConflictDisposition.deterministicMergeRequired;
    }
    return LifeMateConflictDisposition.replayAllowed;
  }

  static LifeMateConflictDisposition _resolvePregnancyDating(
    LifeMateConflictContext context,
  ) {
    // Dating drives gestational age and downstream safety/content/reminders.
    // Any authoritative concurrent dating revision requires explicit review.
    if (context.revisionChanged || context.overlappingFact) {
      return LifeMateConflictDisposition.explicitResolutionRequired;
    }
    return LifeMateConflictDisposition.replayAllowed;
  }

  static LifeMateConflictDisposition _resolveObservation(
    LifeMateConflictContext context,
  ) {
    // Stable logical IDs dedupe exact captures via the equivalent fast path.
    // Distinct observations are additive; a source revision conflict should
    // refresh before retry so server validation can decide without data loss.
    if (context.revisionChanged) {
      return LifeMateConflictDisposition.refreshThenRetry;
    }
    return LifeMateConflictDisposition.replayAllowed;
  }

  static LifeMateConflictDisposition _resolveSharedAuthorization(
    LifeMateConflictContext context,
  ) {
    // Non-revoked shared authorization still depends on authoritative refresh;
    // local state can never independently grant or prolong access.
    if (context.revisionChanged || context.overlappingFact) {
      return LifeMateConflictDisposition.refreshThenRetry;
    }
    return LifeMateConflictDisposition.replayAllowed;
  }
}
