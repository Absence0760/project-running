import 'package:flutter_test/flutter_test.dart';

import '../lib/background_location_nudge.dart';

void main() {
  group('shouldNudgeBackgroundLocation (#57)', () {
    test('nudges on Android when foreground is granted but always is not', () {
      expect(
        shouldNudgeBackgroundLocation(
          isAndroid: true,
          foregroundGranted: true,
          alwaysGranted: false,
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
        ),
        isFalse,
      );
    });
  });
}
