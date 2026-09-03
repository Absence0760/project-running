import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Mirror of `apps/web/src/lib/integrations/strava_sync_result.test.ts`.
void main() {
  test('a finished walk is the only shape that reports complete', () {
    final r = stravaSyncResultFromResponse({
      'imported': 12,
      'skipped': 3,
      'failed': 1,
      'rate_limited': false,
      'complete': true,
    });
    expect(r.complete, isTrue);
    expect(r.rateLimited, isFalse);
    expect([r.imported, r.skipped, r.failed], [12, 3, 1]);
  });

  test('a throttled walk is partial and names the cause', () {
    final r = stravaSyncResultFromResponse({
      'imported': 40,
      'skipped': 0,
      'failed': 0,
      'rate_limited': true,
      'complete': false,
    });
    expect(r.complete, isFalse);
    expect(r.rateLimited, isTrue);
    expect(r.imported, 40);
  });

  test('the other truncation causes are partial without a named cause', () {
    // An upstream error, a malformed page and the 20-page cap all return
    // `rate_limited: false, complete: false`. Before `complete` existed they
    // were indistinguishable from a finished sync, which is the whole bug.
    final r = stravaSyncResultFromResponse({
      'imported': 1000,
      'skipped': 0,
      'failed': 0,
      'rate_limited': false,
      'complete': false,
    });
    expect(r.complete, isFalse);
    expect(r.rateLimited, isFalse);
  });

  test('an absent complete field reads as partial, not as finished', () {
    // The fail-closed direction: a false "partial" costs one extra tap, a
    // false "complete" costs the runs that aged out of the window.
    expect(
      stravaSyncResultFromResponse(
        {'imported': 5, 'skipped': 0, 'failed': 0},
      ).complete,
      isFalse,
    );
    expect(stravaSyncResultFromResponse(<String, Object?>{}).complete, isFalse);
  });

  test('a complete field that is not the boolean true does not earn it', () {
    for (final value in <Object?>['true', 1, <String, Object?>{}, <Object?>[], null, 'yes']) {
      expect(
        stravaSyncResultFromResponse({'complete': value}).complete,
        isFalse,
        reason: 'complete: $value must not read as finished',
      );
    }
  });

  test('rate_limited must be the boolean true to claim a throttle', () {
    for (final value in <Object?>['true', 1, <String, Object?>{}, null]) {
      expect(
        stravaSyncResultFromResponse({'rate_limited': value}).rateLimited,
        isFalse,
      );
    }
  });

  test('an unrecognised payload zeroes the counts and reports partial', () {
    for (final payload in <Object?>[
      null,
      'ok',
      42,
      <Object?>[],
      <Object?>[
        {'imported': 9},
      ],
    ]) {
      final r = stravaSyncResultFromResponse(payload);
      expect(
        [
          r.imported,
          r.skipped,
          r.failed,
          r.rateLimited,
          r.complete,
          r.resumable,
          r.athleteId,
          r.error,
        ],
        [0, 0, 0, false, false, false, null, null],
        reason: 'payload $payload must not read as a sync',
      );
    }
  });

  test('only a non-negative integer is a count', () {
    final r = stravaSyncResultFromResponse({
      'imported': -3,
      'skipped': 4.5,
      'failed': '7',
      'complete': true,
    });
    // A malformed count reads as 0 rather than as a number the banner would
    // then state as fact. Completeness is a separate claim and survives.
    expect([r.imported, r.skipped, r.failed], [0, 0, 0]);
    expect(r.complete, isTrue);
    expect(stravaSyncResultFromResponse({'imported': double.nan}).imported, 0);
    expect(stravaSyncResultFromResponse({'imported': double.infinity}).imported, 0);
    expect(stravaSyncResultFromResponse({'imported': 0}).imported, 0);
  });

  test('a whole double is a count, as it is on the web twin', () {
    // JSON has one number type: web's `Number.isInteger` cannot tell `12`
    // from `12.0`, so neither may this.
    expect(stravaSyncResultFromResponse({'imported': 12.0}).imported, 12);
  });

  test('an embedded error forces partial even when the body claims complete', () {
    final r = stravaSyncResultFromResponse({
      'error': 'strava_not_connected',
      'imported': 0,
      'skipped': 0,
      'failed': 0,
      'complete': true,
    });
    expect(r.error, 'strava_not_connected');
    expect(r.complete, isFalse);
  });

  test('a blank error is no error', () {
    expect(
      stravaSyncResultFromResponse({'error': '   ', 'complete': true}).error,
      isNull,
    );
    expect(
      stravaSyncResultFromResponse({'error': '   ', 'complete': true}).complete,
      isTrue,
    );
    expect(stravaSyncResultFromResponse({'error': 404}).error, isNull);
  });

  test('athlete_id is carried through only as a non-empty string', () {
    expect(stravaSyncResultFromResponse({'athlete_id': '12345'}).athleteId, '12345');
    expect(stravaSyncResultFromResponse({'athlete_id': ''}).athleteId, isNull);
    expect(stravaSyncResultFromResponse({'athlete_id': 12345}).athleteId, isNull);
    expect(stravaSyncResultFromResponse(<String, Object?>{}).athleteId, isNull);
  });

  test('resumable must be the boolean true to claim a resume point', () {
    // Same fail-closed direction as `complete`: telling a runner "sync again
    // to carry on" when nothing was recorded sends them back to a walk that
    // will restart from the beginning and stop in the same place.
    for (final value in <Object?>['true', 1, <String, Object?>{}, null]) {
      expect(
        stravaSyncResultFromResponse({'resumable': value}).resumable,
        isFalse,
      );
    }
    expect(
      stravaSyncResultFromResponse({'resumable': true}).resumable,
      isTrue,
    );
  });

  test('a finished walk is never resumable, whatever the body says', () {
    // A finished window subsumes any point inside it, and the function clears
    // the cursor when it reaches the end. A body claiming both is malformed;
    // resolving it here keeps every surface from having to.
    final r = stravaSyncResultFromResponse({
      'complete': true,
      'resumable': true,
    });
    expect(r.complete, isTrue);
    expect(r.resumable, isFalse);
  });

  test('an embedded error leaves a resume point readable', () {
    // `complete` is forced false by an error, and that must not drag the
    // resume point down with it: a walk that recorded one still has it.
    final r = stravaSyncResultFromResponse({
      'error': 'partial',
      'complete': true,
      'resumable': true,
    });
    expect(r.complete, isFalse);
    expect(r.resumable, isTrue);
  });

  test('the lookback options are ascending, start at the default and end at the max', () {
    expect(kStravaLookbackOptions.first, kStravaLookbackDefaultDays);
    expect(kStravaLookbackOptions.last, kStravaLookbackMaxDays);
    for (var i = 1; i < kStravaLookbackOptions.length; i++) {
      expect(kStravaLookbackOptions[i], greaterThan(kStravaLookbackOptions[i - 1]));
    }
    expect(kStravaLookbackOptions.every(isStravaLookbackReachable), isTrue);
    expect(isStravaLookbackReachable(kStravaLookbackMaxDays + 1), isFalse);
    expect(isStravaLookbackReachable(0), isFalse);
  });
}
