import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/turn_cue_announcer.dart';
import 'package:mobile_android/turn_cues.dart';

TurnCue _cue(double posM, TurnDirection dir) => TurnCue(
      positionM: posM,
      bearingInDeg: 0,
      bearingOutDeg: 90,
      direction: dir,
    );

void main() {
  group('TurnCueAnnouncer', () {
    test('empty cue list announces nothing', () {
      final a = TurnCueAnnouncer(const []);
      expect(a.hasCues, isFalse);
      expect(a.announcementFor(0), isNull);
      expect(a.announcementFor(500), isNull);
    });

    test('straight cues are filtered out', () {
      final a = TurnCueAnnouncer([_cue(500, TurnDirection.straight)]);
      expect(a.hasCues, isFalse);
    });

    test('fires the 300 m band first when approaching a turn', () {
      final a = TurnCueAnnouncer([_cue(1000, TurnDirection.left)]);
      // 320 m ahead — inside 300+window.
      final ann = a.announcementFor(680);
      expect(ann, isNotNull);
      expect(ann!.thresholdM, 300);
      expect(ann.isNow, isFalse);
      expect(ann.cue.direction, TurnDirection.left);
    });

    test('each band fires once per turn, near→far progression', () {
      final a = TurnCueAnnouncer([_cue(1000, TurnDirection.right)]);
      expect(a.announcementFor(700)!.thresholdM, 300);
      // Still in the 300 window but already fired — nothing until next band.
      expect(a.announcementFor(710), isNull);
      expect(a.announcementFor(900)!.thresholdM, 100);
      expect(a.announcementFor(995)!.thresholdM, 0);
      // All bands exhausted.
      expect(a.announcementFor(1000), isNull);
    });

    test('the 0 band marks the "now" announcement', () {
      final a = TurnCueAnnouncer([_cue(200, TurnDirection.left)]);
      // Jump straight to the turn — far bands fire first on the way in, so
      // start close enough that 300/100 already passed.
      a.announcementFor(700); // far past nothing (turn is at 200, behind)
      final fresh = TurnCueAnnouncer([_cue(200, TurnDirection.left)]);
      // Approach: 300 fires, 100 fires, then now.
      expect(fresh.announcementFor(0)!.thresholdM, 300);
      expect(fresh.announcementFor(100)!.thresholdM, 100);
      final now = fresh.announcementFor(190);
      expect(now!.thresholdM, 0);
      expect(now.isNow, isTrue);
    });

    test('a turn well behind the runner is never announced', () {
      final a = TurnCueAnnouncer([_cue(100, TurnDirection.right)]);
      // Runner is 400 m past the turn.
      expect(a.announcementFor(500), isNull);
    });

    test('only the nearest upcoming turn is considered', () {
      final a = TurnCueAnnouncer([
        _cue(500, TurnDirection.left),
        _cue(1500, TurnDirection.right),
      ]);
      // At 480 m the nearest turn (500) is within its now-window → fires it,
      // not the far one.
      final ann = a.announcementFor(480);
      expect(ann!.cue.positionM, 500);
    });

    test('the far turn fires only after the near one is passed', () {
      final a = TurnCueAnnouncer([
        _cue(300, TurnDirection.left),
        _cue(1300, TurnDirection.right),
      ]);
      // Burn through the near turn's bands.
      a.announcementFor(0);
      a.announcementFor(200);
      a.announcementFor(295);
      // Now past the near turn; approach the far one.
      final ann = a.announcementFor(1010);
      expect(ann!.cue.positionM, 1300);
      expect(ann.thresholdM, 300);
    });

    test('slight and uturn directions are announced', () {
      final a = TurnCueAnnouncer([_cue(1000, TurnDirection.uturn)]);
      final ann = a.announcementFor(700);
      expect(ann!.cue.direction, TurnDirection.uturn);
    });

    test('null is returned when no turn is near', () {
      final a = TurnCueAnnouncer([_cue(5000, TurnDirection.left)]);
      expect(a.announcementFor(100), isNull);
    });
  });

  group('reset (per-recording fired state)', () {
    test('a second run over the same route announces every band again', () {
      final a = TurnCueAnnouncer([
        _cue(400, TurnDirection.left),
        _cue(1200, TurnDirection.right),
      ]);
      // Run 1: walk the whole route so every band of every turn latches.
      for (final along in <double>[100, 300, 395, 900, 1100, 1195, 1300]) {
        a.announcementFor(along);
      }
      expect(a.announcementFor(100), isNull,
          reason: 'all bands latched after the first pass');

      a.reset();

      expect(a.announcementFor(100)!.thresholdM, 300);
      expect(a.announcementFor(300)!.thresholdM, 100);
      expect(a.announcementFor(395)!.thresholdM, 0);
      expect(a.announcementFor(900)!.thresholdM, 300);
      expect(a.announcementFor(1100)!.thresholdM, 100);
      expect(a.announcementFor(1195)!.thresholdM, 0);
    });

    test('reset mid-route re-arms the bands already spoken', () {
      final a = TurnCueAnnouncer([_cue(400, TurnDirection.left)]);
      expect(a.announcementFor(100)!.thresholdM, 300);
      expect(a.announcementFor(300)!.thresholdM, 100);
      a.reset();
      expect(a.announcementFor(100)!.thresholdM, 300);
    });

    test('reset on a never-used announcer is a no-op', () {
      final a = TurnCueAnnouncer([_cue(400, TurnDirection.left)]);
      a.reset();
      expect(a.announcementFor(100)!.thresholdM, 300);
    });

    test('reset does not resurrect turns the runner is already past', () {
      final a = TurnCueAnnouncer([_cue(100, TurnDirection.right)]);
      a.reset();
      expect(a.announcementFor(500), isNull);
    });
  });
}
