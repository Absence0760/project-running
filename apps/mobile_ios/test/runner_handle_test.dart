import 'package:flutter_test/flutter_test.dart';

import '../lib/runner_handle.dart';

void main() {
  // Persona-hunt Round 3 finding Privacy #5. Dart twin of
  // `apps/web/src/lib/runner_handle.test.ts` — keep in lockstep.
  group('runnerHandle', () {
    test('returns Runner #ABCD for a v4 uuid (first 4 hex chars, uppercased)',
        () {
      expect(runnerHandle('a1b2c3d4-e5f6-7890-abcd-ef1234567890'),
          'Runner #A1B2');
      expect(runnerHandle('00000000-0000-0000-0000-000000000bad'),
          'Runner #0000');
    });

    test('drops hyphens from the uuid before taking the slice', () {
      expect(runnerHandle('aaa-b2c3-...'), 'Runner #AAAB');
    });

    test('returns plain "Runner" for null / empty / too-short input', () {
      expect(runnerHandle(null), 'Runner');
      expect(runnerHandle(''), 'Runner');
      expect(runnerHandle('a-1'), 'Runner');
    });

    test('deterministic — same uuid produces same handle on every call', () {
      const id = 'b2c3d4e5-f6a7-8901-bcde-f23456789012';
      expect(runnerHandle(id), runnerHandle(id));
    });
  });

  group('shouldRevealDisplayName', () {
    test('anon viewer → false', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: null,
          runnerUserId: 'r-1',
          viewerFollowsRunner: false,
          runnerFollowsViewer: false,
        ),
        false,
      );
    });

    test('missing runnerUserId → false (defensive)', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'v-1',
          runnerUserId: null,
          viewerFollowsRunner: false,
          runnerFollowsViewer: false,
        ),
        false,
      );
    });

    test('self-view → true', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'same-id',
          runnerUserId: 'same-id',
          viewerFollowsRunner: false,
          runnerFollowsViewer: false,
        ),
        true,
      );
    });

    test('viewer follows runner → true', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'v',
          runnerUserId: 'r',
          viewerFollowsRunner: true,
          runnerFollowsViewer: false,
        ),
        true,
      );
    });

    test('runner follows viewer → true', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'v',
          runnerUserId: 'r',
          viewerFollowsRunner: false,
          runnerFollowsViewer: true,
        ),
        true,
      );
    });

    test('signed-in stranger with no follow edge → false', () {
      expect(
        shouldRevealDisplayName(
          viewerUserId: 'stranger',
          runnerUserId: 'runner',
          viewerFollowsRunner: false,
          runnerFollowsViewer: false,
        ),
        false,
      );
    });
  });
}
