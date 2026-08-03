import 'package:flutter_test/flutter_test.dart';

import '../lib/pro_sellable.dart';

/// The mobile half of the hollow-subscription gate (decisions §466). Every
/// unreadable answer must resolve to "nothing live" — a client that cannot
/// establish a perk is live must not take a payment.
void main() {
  group('parseProPerks', () {
    test('reads both flags off the manifest', () {
      final p = parseProPerks('{"coach":true,"route_gen":false}');
      expect(p.coach, isTrue);
      expect(p.routeGen, isFalse);
      expect(p.sellable, isTrue);
    });

    test('sellable when either perk is live, not when neither is', () {
      expect(parseProPerks('{"coach":false,"route_gen":true}').sellable, isTrue);
      expect(parseProPerks('{"coach":true,"route_gen":true}').sellable, isTrue);
      expect(
          parseProPerks('{"coach":false,"route_gen":false}').sellable, isFalse);
    });

    test('missing keys read as off', () {
      final p = parseProPerks('{}');
      expect(p.coach, isFalse);
      expect(p.routeGen, isFalse);
      expect(p.sellable, isFalse);
    });

    test('non-boolean truthy values read as off', () {
      // A string "true", 1, or a nested object must not sell a subscription.
      expect(parseProPerks('{"coach":"true"}').sellable, isFalse);
      expect(parseProPerks('{"coach":1}').sellable, isFalse);
      expect(parseProPerks('{"route_gen":{"on":true}}').sellable, isFalse);
    });

    test('malformed, empty, and non-object bodies read as off', () {
      for (final body in ['', 'not json', '<html>404</html>', '[true]', 'true', 'null']) {
        expect(parseProPerks(body).sellable, isFalse, reason: 'body: $body');
      }
    });

    test('a snake_case-only contract — camelCase does not enable selling', () {
      // The web manifest emits `route_gen`; accepting `routeGen` too would
      // let a drifted server shape silently re-enable the storefront.
      expect(parseProPerks('{"routeGen":true}').sellable, isFalse);
    });
  });

  test('ProPerks.none is the fail-closed default', () {
    expect(ProPerks.none.coach, isFalse);
    expect(ProPerks.none.routeGen, isFalse);
    expect(ProPerks.none.sellable, isFalse);
  });
}
