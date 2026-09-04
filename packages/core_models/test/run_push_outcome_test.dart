import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Two states, and the difference between them is the whole point: a retryable
/// failure comes back on its own, a blocked one never will. decisions § 1070.
void main() {
  test('a run named by neither set landed', () {
    const outcome = RunPushOutcome();
    expect(outcome.failedIds, isEmpty);
    expect(outcome.failedCount, 0);
    expect(outcome.isEmpty, isTrue);
  });

  test('failedIds is the union — the set a caller subtracts before marking',
      () {
    const outcome = RunPushOutcome(
      retryable: {'r-net'},
      blocked: {'r-big': RunPushBlockReason.trackTooLarge},
    );
    expect(outcome.failedIds, {'r-net', 'r-big'});
    expect(outcome.failedCount, 2);
    expect(outcome.isEmpty, isFalse);
  });

  test('a blocked-only outcome is still a failure', () {
    // A caller that reads only `retryable` would mark a parked run synced and
    // lose it: the row was never upserted.
    const outcome = RunPushOutcome(
      blocked: {'r-big': RunPushBlockReason.trackTooLarge},
    );
    expect(outcome.isEmpty, isFalse);
    expect(outcome.failedIds, {'r-big'});
  });

  test('the reason names are on-disk values', () {
    // `LocalRunStore`'s `blocked_runs.json` persists `reason.name`, so a rename
    // orphans every run already parked under the old spelling — which then
    // reads as retryable again and resumes the loop the park exists to stop.
    expect(RunPushBlockReason.trackTooLarge.name, 'trackTooLarge');
    expect(RunPushBlockReason.values, hasLength(1),
        reason: 'decisions § 986 refused a taxonomy with no reachable member; '
            'a second member is earned by measuring a second permanent '
            'failure, and brings a sidecar-compatibility question with it');
  });
}
