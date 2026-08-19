import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/run_screen.dart';

/// Issues #784 / #785: the "Allow all the time" disclosure fires when it
/// actually matters — the runner came back to a recording run that received
/// no GPS fix while the app was off screen — never at the start of every
/// session, and never more than once per run.
void main() {
  final left = DateTime.utc(2026, 8, 18, 7, 30);
  final back = left.add(const Duration(minutes: 4));

  bool disclose({
    bool limitedGrant = true,
    bool recording = true,
    bool manualPaused = false,
    bool alreadyDisclosed = false,
    DateTime? leftForegroundAt,
    DateTime? returnedAt,
    DateTime? lastFixAt,
  }) =>
      shouldDiscloseBackgroundLocationLimit(
        limitedGrant: limitedGrant,
        recording: recording,
        manualPaused: manualPaused,
        alreadyDisclosed: alreadyDisclosed,
        leftForegroundAt: leftForegroundAt ?? left,
        returnedAt: returnedAt ?? back,
        lastFixAt: lastFixAt ?? left.subtract(const Duration(seconds: 2)),
      );

  group('shouldDiscloseBackgroundLocationLimit', () {
    test('discloses when no fix arrived while the app was away', () {
      expect(disclose(), isTrue);
    });

    test('stays silent when fixes kept arriving in the background', () {
      // Android does not always cut delivery under a foreground service —
      // telling this runner their tracking paused would be false.
      expect(
        disclose(lastFixAt: left.add(const Duration(minutes: 2))),
        isFalse,
      );
    });

    test('stays silent for a full-permission grant', () {
      expect(disclose(limitedGrant: false), isFalse);
    });

    test('stays silent when the run is not recording', () {
      // The idle screen backgrounding is not a recording gap, which is what
      // made the old start-of-session banner read as "something is broken".
      expect(disclose(recording: false), isFalse);
    });

    test('stays silent while the runner has the run manually paused', () {
      // The recorder drops every fix while paused, so a stale fix says
      // nothing about the permission.
      expect(disclose(manualPaused: true), isFalse);
    });

    test('discloses at most once per run', () {
      expect(disclose(alreadyDisclosed: true), isFalse);
    });

    test('stays silent for an app switch shorter than a fix interval', () {
      expect(
        disclose(returnedAt: left.add(const Duration(seconds: 5))),
        isFalse,
      );
    });

    test('the away threshold is inclusive at its edge', () {
      expect(
        disclose(returnedAt: left.add(kBackgroundLocationDisclosureMinAway)),
        isTrue,
      );
    });

    test('stays silent for a run that never had a GPS fix', () {
      // Indoor / treadmill: no fix while away is the norm, not evidence of
      // a permission problem.
      expect(
        shouldDiscloseBackgroundLocationLimit(
          limitedGrant: true,
          recording: true,
          manualPaused: false,
          alreadyDisclosed: false,
          leftForegroundAt: left,
          returnedAt: back,
          lastFixAt: null,
        ),
        isFalse,
      );
    });

    test('a fix landing exactly at the moment of leaving is not coverage', () {
      expect(disclose(lastFixAt: left), isTrue);
    });
  });
}
