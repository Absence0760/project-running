import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	OffRouteAlertDetector,
	offRouteEscalationEnabled,
	OFF_ROUTE_ALERT_DISTANCE_M,
	OFF_ROUTE_ALERT_SUSTAIN_MS,
} from './off_route_alert';

const NOW = 1_700_000_000_000;
const OVER = OFF_ROUTE_ALERT_DISTANCE_M + 10;

test('on-route never fires', () => {
	const d = new OffRouteAlertDetector();
	assert.equal(d.update(0, NOW), false);
	assert.equal(d.update(10, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS * 10), false);
	assert.equal(d.hasFired, false);
});

test('null distance (no route / no fix) never fires and resets', () => {
	const d = new OffRouteAlertDetector();
	assert.equal(d.update(OVER, NOW), false);
	assert.equal(d.update(null, NOW + 1000), false);
	// Clock was reset — a fresh over-threshold run must restart the window.
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS + 2000), false);
});

test('a single over-threshold spike does not fire', () => {
	const d = new OffRouteAlertDetector();
	assert.equal(d.update(OVER, NOW), false);
});

test('fires exactly once after sustained off-route beyond the window', () => {
	const d = new OffRouteAlertDetector();
	assert.equal(d.update(OVER, NOW), false, 'clock starts');
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS - 1), false, 'still within window');
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS), true, 'window reached → fire');
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS + 5000), false, 'latched, never re-fires');
	assert.equal(d.hasFired, true);
});

test('at exactly the threshold distance the clock does not run', () => {
	const d = new OffRouteAlertDetector();
	// <= threshold is on-route; must be strictly beyond.
	assert.equal(d.update(OFF_ROUTE_ALERT_DISTANCE_M, NOW), false);
	assert.equal(d.update(OFF_ROUTE_ALERT_DISTANCE_M, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS * 2), false);
});

test('a dip back on-route resets the sustain clock (debounce)', () => {
	const d = new OffRouteAlertDetector();
	assert.equal(d.update(OVER, NOW), false);
	// Brief return under the threshold before the window elapses.
	assert.equal(d.update(0, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS - 1), false);
	// Off again — the clock restarts, so the original elapsed time doesn't count.
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS), false);
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS * 2), true);
});

test('a non-finite distance never arms the clock and never spends the latch', () => {
	for (const bogus of [NaN, Infinity, -Infinity]) {
		const d = new OffRouteAlertDetector();
		assert.equal(d.update(bogus, NOW), false, `${bogus} must not start the clock`);
		assert.equal(
			d.update(bogus, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS * 10),
			false,
			`${bogus} must never fire`,
		);
		assert.equal(d.hasFired, false, `${bogus} must not spend the latch`);
	}
});

test('a non-finite reading resets the clock the way a null one does', () => {
	const d = new OffRouteAlertDetector();
	assert.equal(d.update(OVER, NOW), false, 'clock starts');
	assert.equal(d.update(NaN, NOW + 1000), false);
	// The unusable reading reset the window, so the original anchor is gone.
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS), false);
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS * 2), true);
});

test('a non-finite run leaves a later genuine departure still able to fire', () => {
	const d = new OffRouteAlertDetector();
	// A whole run's worth of unusable readings.
	for (let i = 0; i < 20; i++) d.update(Infinity, NOW + i * OFF_ROUTE_ALERT_SUSTAIN_MS);
	const later = NOW + 100 * OFF_ROUTE_ALERT_SUSTAIN_MS;
	assert.equal(d.update(500, later), false, 'clock starts on the real departure');
	assert.equal(d.update(500, later + OFF_ROUTE_ALERT_SUSTAIN_MS), true, 'the latch was still there');
});

test('a backwards clock step re-anchors instead of wedging the detector', () => {
	const d = new OffRouteAlertDetector();
	assert.equal(d.update(500, NOW), false, 'anchor at NOW');
	// NTP corrects the device clock back an hour mid-run.
	const back = NOW - 3_600_000;
	assert.equal(d.update(500, back), false, 're-anchored, window restarts');
	assert.equal(
		d.update(500, back + OFF_ROUTE_ALERT_SUSTAIN_MS - 1),
		false,
		'still inside the restarted window',
	);
	assert.equal(
		d.update(500, back + OFF_ROUTE_ALERT_SUSTAIN_MS),
		true,
		'fires a sustain window after the corrected clock, not an hour later',
	);
});

test('a backwards step does not shorten the window either', () => {
	const d = new OffRouteAlertDetector();
	assert.equal(d.update(500, NOW), false);
	// A step back of less than the window must still require a full window
	// from the corrected reading — it must not read as elapsed time.
	assert.equal(d.update(500, NOW - 10_000), false);
	assert.equal(d.update(500, NOW - 10_000 + OFF_ROUTE_ALERT_SUSTAIN_MS - 1), false);
	assert.equal(d.update(500, NOW - 10_000 + OFF_ROUTE_ALERT_SUSTAIN_MS), true);
});

test('reset() re-arms a fired detector', () => {
	const d = new OffRouteAlertDetector();
	d.update(OVER, NOW);
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS), true);
	d.reset();
	assert.equal(d.hasFired, false);
	assert.equal(d.update(OVER, NOW), false, 'clock restarts after reset');
	assert.equal(d.update(OVER, NOW + OFF_ROUTE_ALERT_SUSTAIN_MS), true);
});

test('custom threshold + sustain are honoured', () => {
	const d = new OffRouteAlertDetector(200, 30_000);
	assert.equal(d.update(150, NOW), false, 'under custom threshold');
	assert.equal(d.update(250, NOW), false, 'clock starts at custom threshold');
	assert.equal(d.update(250, NOW + 30_000), true);
});

test('offRouteEscalationEnabled: truthy only for explicit affirmatives', () => {
	for (const v of ['1', 'true', 'TRUE', 'yes', 'on', ' On ']) {
		assert.equal(offRouteEscalationEnabled(v), true, `${v} should enable`);
	}
});

test('offRouteEscalationEnabled: fail-closed for unset / falsy', () => {
	for (const v of [undefined, null, '', '0', 'false', 'off', 'no', 'maybe']) {
		assert.equal(offRouteEscalationEnabled(v), false, `${String(v)} should stay off`);
	}
});
