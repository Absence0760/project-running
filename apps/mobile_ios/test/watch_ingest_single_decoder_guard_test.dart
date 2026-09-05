// Source-level guard: the watch-ingest bridge has ONE decoder.
//
// The same method-channel payload reaches two places — decoded immediately
// when the runner is signed in, enqueued and decoded on the next sign-in when
// they are not. It used to be decoded by two hand-written copies, and the
// copies had drifted in both directions over the same bridge payload: the
// signed-in one never learned the per-point `bpm` that
// `docs/backend/metadata.md` says the watch-ingest decoder reads, and the
// queue's never learned that the bridge sends `track` as JSON TEXT, so a run
// that arrived while signed out was replayed with no track at all. Neither
// omission is visible from either file on its own, which is why this is a
// guard and not a comment (decisions § 1254).
//
// Anchored on the decode ITSELF, not on a name: constructing a `Run` or a
// `Waypoint` inside the bridge, or assembling a metadata map there, IS the
// second decoder however it is spelled.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The `WatchIngest` class body, from its declaration to the following
/// top-level one.
String _watchIngestBody() {
  final src = File('lib/main.dart').readAsStringSync();
  final start = src.indexOf('class WatchIngest {');
  expect(start >= 0, true, reason: 'WatchIngest is gone or renamed');
  final next = src.indexOf('\nclass ', start + 1);
  final body = src.substring(start, next > start ? next : src.length);
  expect(body.contains("MethodChannel('run_app/watch_ingest')"), true,
      reason: 'the extracted body is not the bridge — every check below '
          'would pass vacuously');
  return body;
}

void main() {
  test('the bridge decodes through runFromWatchPayload and nowhere else', () {
    final body = _watchIngestBody();
    expect(body.contains('runFromWatchPayload('), true,
        reason: 'the signed-in branch must reuse the queue decoder');
    expect(RegExp(r'\bcm\.Run\(').hasMatch(body), false,
        reason: 'building a Run here is a second decoder for a payload that '
            'already has one, and the two will drift');
    expect(RegExp(r'\bcm\.Waypoint\(').hasMatch(body), false,
        reason: 'decoding track points here is the divergence that lost an '
            'Apple Watch run its whole track on the queued path');
    expect(body.contains('MetadataKeys.'), false,
        reason: 'a metadata allowlist here is the second allowlist that '
            'dropped hr_coverage');
  });

  test('one payload is normalised once, for both branches', () {
    final body = _watchIngestBody();
    expect(RegExp(r'args\.entries').allMatches(body).length, 1,
        reason: 'the enqueued map and the decoded map must be the same map; '
            'two constructions is how the two branches come to disagree '
            'about what the watch sent');
    expect(RegExp(r'queue\.enqueue\(').allMatches(body).length, 1,
        reason: 'exactly one enqueue path');
  });
}
