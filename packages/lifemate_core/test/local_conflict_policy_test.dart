import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_core/lifemate_core.dart';

void main() {
  group('LifeMateConflictPolicy', () {
    test('acknowledges only proven equivalent logical event', () {
      for (final domain in LifeMateConflictDomain.values) {
        expect(
          LifeMateConflictPolicy.resolve(
            LifeMateConflictContext(
              domain: domain,
              sameLogicalEvent: true,
              sameCanonicalValue: true,
            ),
          ),
          LifeMateConflictDisposition.acknowledgeEquivalent,
        );
      }
    });

    test('conflicting adherence state never silently overwrites history', () {
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.adherence,
            sameLogicalEvent: true,
            sameCanonicalValue: false,
          ),
        ),
        LifeMateConflictDisposition.explicitResolutionRequired,
      );
    });

    test('unmatched adherence conflict refreshes before retry', () {
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.adherence,
          ),
        ),
        LifeMateConflictDisposition.refreshThenRetry,
      );
    });

    test('concurrent treatment and care event edits require resolution', () {
      for (final domain in <LifeMateConflictDomain>[
        LifeMateConflictDomain.treatment,
        LifeMateConflictDomain.careEvent,
      ]) {
        expect(
          LifeMateConflictPolicy.resolve(
            LifeMateConflictContext(
              domain: domain,
              expectedRevision: '7',
              serverRevision: '8',
            ),
          ),
          LifeMateConflictDisposition.explicitResolutionRequired,
        );
      }
    });

    test('same treatment revision can replay', () {
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.treatment,
            expectedRevision: '7',
            serverRevision: '7',
          ),
        ),
        LifeMateConflictDisposition.replayAllowed,
      );
    });

    test('overlapping women cycle facts require deterministic merge', () {
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.womenHealthCycle,
            overlappingFact: true,
          ),
        ),
        LifeMateConflictDisposition.deterministicMergeRequired,
      );
    });

    test('pregnancy dating revision never uses last-write-wins', () {
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.pregnancyDating,
            expectedRevision: 'dating-v3',
            serverRevision: 'dating-v4',
          ),
        ),
        LifeMateConflictDisposition.explicitResolutionRequired,
      );
    });

    test('distinct observation can replay but changed source refreshes first', () {
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.observation,
          ),
        ),
        LifeMateConflictDisposition.replayAllowed,
      );
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.observation,
            expectedRevision: '1',
            serverRevision: '2',
          ),
        ),
        LifeMateConflictDisposition.refreshThenRetry,
      );
    });

    test('authoritative shared revocation always fails closed', () {
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.sharedAuthorization,
            sameLogicalEvent: true,
            sameCanonicalValue: true,
            authoritativeAccessRevoked: true,
          ),
        ),
        LifeMateConflictDisposition.invalidateSharedAccess,
      );
    });

    test('stale local shared state cannot infer revocation or grant', () {
      expect(
        LifeMateConflictPolicy.resolve(
          const LifeMateConflictContext(
            domain: LifeMateConflictDomain.sharedAuthorization,
            expectedRevision: 'grant-3',
            serverRevision: 'grant-4',
          ),
        ),
        LifeMateConflictDisposition.refreshThenRetry,
      );
    });
  });
}
