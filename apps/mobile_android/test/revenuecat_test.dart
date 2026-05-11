import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/revenuecat.dart';

void main() {
  setUpAll(() {
    // No env keys → wrapper reports unconfigured. Tests that need to
    // simulate the configured state pass a `keyOverride`.
    dotenv.loadFromString(isOptional: true);
  });

  tearDown(resetRevenueCatStateForTest);

  group('isRevenueCatConfigured', () {
    test('false when no platform key is in dotenv.env', () {
      expect(isRevenueCatConfigured(), isFalse);
    });

    test('true when keyOverride is non-empty', () {
      expect(
        isRevenueCatConfigured(keyOverride: 'rc_test_key'),
        isTrue,
      );
    });

    test('false when keyOverride is empty', () {
      expect(isRevenueCatConfigured(keyOverride: ''), isFalse);
    });
  });

  group('configureRevenueCat', () {
    test('returns false when no API key is provided', () async {
      final ok = await configureRevenueCat('user-1');
      expect(ok, isFalse);
    });

    test('keyOverride is honoured for tests', () async {
      // Without a key override, the wrapper has nothing to feed into
      // Purchases.configure. We can't actually init the SDK in a
      // headless test (no platform channel), so the path under test
      // here is: "given a key, the wrapper tries to configure and
      // surfaces the failure as false". An exception inside
      // Purchases.configure is swallowed and false is returned.
      final ok = await configureRevenueCat(
        'user-1',
        keyOverride: 'rc_test_key',
      );
      // Headless test → MissingPluginException inside Purchases →
      // wrapper catches and returns false. The contract under test is
      // "no crashes on a host-test runner".
      expect(ok, isFalse);
    });
  });

  group('startProCheckout', () {
    test('returns PurchaseResult.notConfigured when SDK has no API key',
        () async {
      final r = await startProCheckout('user-1');
      expect(r, PurchaseResult.notConfigured);
    });
  });

  group('managementUrl', () {
    test('returns null when SDK has no API key', () async {
      final url = await managementUrl('user-1');
      expect(url, isNull);
    });
  });
}
