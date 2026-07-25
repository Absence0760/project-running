import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/off_route_alert.dart';

const int now = 1700000000000;
const double over = offRouteAlertDistanceM + 10;

void main() {
  test('on-route never fires', () {
    final d = OffRouteAlertDetector();
    expect(d.update(0, now), false);
    expect(d.update(10, now + offRouteAlertSustainMs * 10), false);
    expect(d.hasFired, false);
  });

  test('null distance (no route / no fix) never fires and resets', () {
    final d = OffRouteAlertDetector();
    expect(d.update(over, now), false);
    expect(d.update(null, now + 1000), false);
    expect(d.update(over, now + offRouteAlertSustainMs + 2000), false);
  });

  test('a single over-threshold spike does not fire', () {
    final d = OffRouteAlertDetector();
    expect(d.update(over, now), false);
  });

  test('fires exactly once after sustained off-route beyond the window', () {
    final d = OffRouteAlertDetector();
    expect(d.update(over, now), false);
    expect(d.update(over, now + offRouteAlertSustainMs - 1), false);
    expect(d.update(over, now + offRouteAlertSustainMs), true);
    expect(d.update(over, now + offRouteAlertSustainMs + 5000), false);
    expect(d.hasFired, true);
  });

  test('at exactly the threshold distance the clock does not run', () {
    final d = OffRouteAlertDetector();
    expect(d.update(offRouteAlertDistanceM, now), false);
    expect(d.update(offRouteAlertDistanceM, now + offRouteAlertSustainMs * 2), false);
  });

  test('a dip back on-route resets the sustain clock (debounce)', () {
    final d = OffRouteAlertDetector();
    expect(d.update(over, now), false);
    expect(d.update(0, now + offRouteAlertSustainMs - 1), false);
    expect(d.update(over, now + offRouteAlertSustainMs), false);
    expect(d.update(over, now + offRouteAlertSustainMs * 2), true);
  });

  test('reset() re-arms a fired detector', () {
    final d = OffRouteAlertDetector();
    d.update(over, now);
    expect(d.update(over, now + offRouteAlertSustainMs), true);
    d.reset();
    expect(d.hasFired, false);
    expect(d.update(over, now), false);
    expect(d.update(over, now + offRouteAlertSustainMs), true);
  });

  test('custom threshold + sustain are honoured', () {
    final d = OffRouteAlertDetector(thresholdM: 200, sustainMs: 30000);
    expect(d.update(150, now), false);
    expect(d.update(250, now), false);
    expect(d.update(250, now + 30000), true);
  });

  test('offRouteEscalationEnabled: truthy only for explicit affirmatives', () {
    for (final v in ['1', 'true', 'TRUE', 'yes', 'on', ' On ']) {
      expect(offRouteEscalationEnabled(v), true, reason: '$v should enable');
    }
  });

  test('offRouteEscalationEnabled: fail-closed for unset / falsy', () {
    for (final v in [null, '', '0', 'false', 'off', 'no', 'maybe']) {
      expect(offRouteEscalationEnabled(v), false, reason: '$v should stay off');
    }
  });

  group('run-screen wiring', () {
    // The detector latches once per run INSIDE update(), so any
    // can't-deliver condition checked after the call has already spent the
    // runner's one escalation for that run: a later, genuinely lost
    // departure — with the live share now on and every gate satisfied —
    // can never notify the contact. Reaching the fire path in a widget test
    // needs a real beginLiveBroadcast round-trip, so the ordering is pinned
    // at the source, the same way the run-screen hot-path invariants are.
    late String source;
    setUpAll(() {
      source = File('lib/screens/run_screen.dart').readAsStringSync();
    });

    test('deliverability is checked before the detector spends its latch', () {
      final gate = RegExp(
        r'if \(detector != null &&[^)]*\)\s*\{',
      ).firstMatch(source);
      expect(gate, isNotNull,
          reason: 'could not find the detector gate in _onSnapshot — if it '
              'was renamed, update this guard');
      expect(
        gate!.group(0),
        contains('_offRouteEscalationDeliverable'),
        reason: 'the sustain clock must only run while an escalation can '
            'actually reach the contact',
      );
    });

    test('_escalateOffRoute holds no post-latch bail-out', () {
      final body = RegExp(
        r'void _escalateOffRoute\(\)\s*\{[\s\S]*?\n  \}',
      ).firstMatch(source);
      expect(body, isNotNull);
      expect(
        body!.group(0)!.contains('isActive'),
        isFalse,
        reason: 'a broadcast check here runs after detector.update() has '
            'already latched — it belongs in the gate that feeds the '
            'detector',
      );
    });
  });
}
