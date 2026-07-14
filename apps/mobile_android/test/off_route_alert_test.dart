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
}
