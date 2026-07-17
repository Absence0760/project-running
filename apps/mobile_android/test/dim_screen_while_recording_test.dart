// Tests for the "dim screen while recording" battery-saver (issue #271):
// the `Preferences.dimScreenWhileRecording` per-device pref (default off,
// round-trips through SharedPreferences) and the pure `shouldDimRecordingMap`
// gate the run screen uses to decide whether to darken the live map.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/preferences.dart';
import '../lib/screens/run_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Preferences.dimScreenWhileRecording', () {
    test('defaults to false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.dimScreenWhileRecording, isFalse);
    });

    test('round-trips through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      await prefs.setDimScreenWhileRecording(true);
      expect(prefs.dimScreenWhileRecording, isTrue);

      final reloaded = Preferences();
      await reloaded.init();
      expect(reloaded.dimScreenWhileRecording, isTrue);
    });

    test('resetAccountScopedPrefs clears it back to false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await prefs.setDimScreenWhileRecording(true);

      await prefs.resetAccountScopedPrefs();
      expect(prefs.dimScreenWhileRecording, isFalse);
    });
  });

  group('shouldDimRecordingMap', () {
    test('dims only while recording with keep-screen-on and the toggle on', () {
      expect(
        shouldDimRecordingMap(
          isCountdown: false,
          keepScreenOn: true,
          dimWhileRecording: true,
        ),
        isTrue,
      );
    });

    test('never dims during the countdown (it paints its own scrim)', () {
      expect(
        shouldDimRecordingMap(
          isCountdown: true,
          keepScreenOn: true,
          dimWhileRecording: true,
        ),
        isFalse,
      );
    });

    test('no dim when keep-screen-on is off (nothing to dim)', () {
      expect(
        shouldDimRecordingMap(
          isCountdown: false,
          keepScreenOn: false,
          dimWhileRecording: true,
        ),
        isFalse,
      );
    });

    test('no dim when the toggle is off (default behaviour)', () {
      expect(
        shouldDimRecordingMap(
          isCountdown: false,
          keepScreenOn: true,
          dimWhileRecording: false,
        ),
        isFalse,
      );
    });
  });
}
