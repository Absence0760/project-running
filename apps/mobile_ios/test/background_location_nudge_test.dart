import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/background_location_nudge.dart';
import '../lib/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('shouldNudgeBackgroundLocation (#57)', () {
    test('nudges on Android when foreground is granted but always is not', () {
      expect(
        shouldNudgeBackgroundLocation(
          isAndroid: true,
          foregroundGranted: true,
          alwaysGranted: false,
          alreadyDismissed: false,
        ),
        isTrue,
      );
    });

    test('no nudge once always-on is granted', () {
      expect(
        shouldNudgeBackgroundLocation(
          isAndroid: true,
          foregroundGranted: true,
          alwaysGranted: true,
          alreadyDismissed: false,
        ),
        isFalse,
      );
    });

    test('no nudge before foreground location is granted', () {
      expect(
        shouldNudgeBackgroundLocation(
          isAndroid: true,
          foregroundGranted: false,
          alwaysGranted: false,
          alreadyDismissed: false,
        ),
        isFalse,
      );
    });

    test('never nudges on iOS', () {
      expect(
        shouldNudgeBackgroundLocation(
          isAndroid: false,
          foregroundGranted: true,
          alwaysGranted: false,
          alreadyDismissed: false,
        ),
        isFalse,
      );
    });

    test('no nudge after a dismissal (#266)', () {
      expect(
        shouldNudgeBackgroundLocation(
          isAndroid: true,
          foregroundGranted: true,
          alwaysGranted: false,
          alreadyDismissed: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldRearmBackgroundLocationNudge (#266)', () {
    test('re-arms when always-on is granted after a dismissal', () {
      expect(
        shouldRearmBackgroundLocationNudge(
          alwaysGranted: true,
          alreadyDismissed: true,
        ),
        isTrue,
      );
    });

    test('no re-arm while always-on is still missing', () {
      expect(
        shouldRearmBackgroundLocationNudge(
          alwaysGranted: false,
          alreadyDismissed: true,
        ),
        isFalse,
      );
    });

    test('no re-arm when nothing was dismissed', () {
      expect(
        shouldRearmBackgroundLocationNudge(
          alwaysGranted: true,
          alreadyDismissed: false,
        ),
        isFalse,
      );
    });

    test('dismiss then grant then revoke ends up nudging again', () {
      var dismissed = true;
      if (shouldRearmBackgroundLocationNudge(
        alwaysGranted: true,
        alreadyDismissed: dismissed,
      )) {
        dismissed = false;
      }
      expect(
        shouldNudgeBackgroundLocation(
          isAndroid: true,
          foregroundGranted: true,
          alwaysGranted: false,
          alreadyDismissed: dismissed,
        ),
        isTrue,
      );
    });
  });

  group('Preferences.backgroundLocationNudgeDismissed (#266)', () {
    test('defaults to false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.backgroundLocationNudgeDismissed, isFalse);
    });

    test('a dismissal persists across a fresh Preferences instance', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await prefs.setBackgroundLocationNudgeDismissed(true);

      final reloaded = Preferences();
      await reloaded.init();
      expect(reloaded.backgroundLocationNudgeDismissed, isTrue);
      expect(
        shouldNudgeBackgroundLocation(
          isAndroid: true,
          foregroundGranted: true,
          alwaysGranted: false,
          alreadyDismissed: reloaded.backgroundLocationNudgeDismissed,
        ),
        isFalse,
      );
    });

    test('clearing the flag re-enables the nudge', () async {
      SharedPreferences.setMockInitialValues(
          {'background_location_nudge_dismissed': true});
      final prefs = Preferences();
      await prefs.init();
      expect(prefs.backgroundLocationNudgeDismissed, isTrue);
      await prefs.setBackgroundLocationNudgeDismissed(false);
      expect(prefs.backgroundLocationNudgeDismissed, isFalse);
    });
  });
}
