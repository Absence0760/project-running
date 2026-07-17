import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/battery_optimisation_hint.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('openBatteryOptimisationExemption (issue #260)', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(batterySettingsChannel, null);
    });

    test('opens the battery-optimisation settings, no App Info fallback',
        () async {
      String? invoked;
      var fallbackCalls = 0;
      messenger.setMockMethodCallHandler(batterySettingsChannel, (call) async {
        invoked = call.method;
        return true;
      });

      await openBatteryOptimisationExemption(
        isAndroid: true,
        openAppSettingsFallback: () async => fallbackCalls++,
      );

      expect(invoked, 'openBatteryOptimisationSettings');
      expect(fallbackCalls, 0);
    });

    test('falls back to App Info when the intent cannot resolve', () async {
      var fallbackCalls = 0;
      messenger.setMockMethodCallHandler(
          batterySettingsChannel, (call) async => false);

      await openBatteryOptimisationExemption(
        isAndroid: true,
        openAppSettingsFallback: () async => fallbackCalls++,
      );

      expect(fallbackCalls, 1);
    });

    test('falls back to App Info when the channel throws', () async {
      var fallbackCalls = 0;
      messenger.setMockMethodCallHandler(batterySettingsChannel, (call) async {
        throw PlatformException(code: 'boom');
      });

      await openBatteryOptimisationExemption(
        isAndroid: true,
        openAppSettingsFallback: () async => fallbackCalls++,
      );

      expect(fallbackCalls, 1);
    });

    test('falls back to App Info when no handler is registered', () async {
      var fallbackCalls = 0;

      await openBatteryOptimisationExemption(
        isAndroid: true,
        openAppSettingsFallback: () async => fallbackCalls++,
      );

      expect(fallbackCalls, 1);
    });

    test('skips the channel entirely off Android', () async {
      var channelCalls = 0;
      var fallbackCalls = 0;
      messenger.setMockMethodCallHandler(batterySettingsChannel, (call) async {
        channelCalls++;
        return true;
      });

      await openBatteryOptimisationExemption(
        isAndroid: false,
        openAppSettingsFallback: () async => fallbackCalls++,
      );

      expect(channelCalls, 0);
      expect(fallbackCalls, 1);
    });

    test('never throws when the fallback itself fails', () async {
      messenger.setMockMethodCallHandler(
          batterySettingsChannel, (call) async => false);

      await openBatteryOptimisationExemption(
        isAndroid: true,
        openAppSettingsFallback: () async => throw Exception('no settings'),
      );
    });
  });
}
