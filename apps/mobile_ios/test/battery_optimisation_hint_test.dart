import 'package:flutter_test/flutter_test.dart';

import '../lib/battery_optimisation_hint.dart';

void main() {
  group('shouldShowBatteryOptHint (persona round-5)', () {
    test('shows on Android the first time', () {
      expect(
        shouldShowBatteryOptHint(isAndroid: true, alreadyShown: false),
        isTrue,
      );
    });

    test('does not show again once shown', () {
      expect(
        shouldShowBatteryOptHint(isAndroid: true, alreadyShown: true),
        isFalse,
      );
    });

    test('never shows on iOS (no OEM app-killers)', () {
      expect(
        shouldShowBatteryOptHint(isAndroid: false, alreadyShown: false),
        isFalse,
      );
    });

    test('never shows on iOS even if not yet shown', () {
      expect(
        shouldShowBatteryOptHint(isAndroid: false, alreadyShown: true),
        isFalse,
      );
    });
  });
}
