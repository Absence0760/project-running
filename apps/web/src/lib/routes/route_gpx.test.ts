import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toRouteGpxWithMarkers, type RouteGpxMarker } from './route_gpx';

const COORDS_3: [number, number][] = [
	[8.54, 47.37],
	[8.541, 47.371],
	[8.542, 47.372]
];
const ELEVS_3 = [400, 410, 420];

function marker(over: Partial<RouteGpxMarker> = {}): RouteGpxMarker {
	return {
		label: 'Aid 1',
		lat: 47.371,
		lng: 8.541,
		kind: 'aid_station',
		meta: {},
		...over
	};
}

test('toRouteGpxWithMarkers — has GPX 1.1 namespace + creator', () => {
	const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, []);
	assert.match(xml, /<gpx version="1.1" creator="Threkir"/);
	assert.match(xml, /xmlns="http:\/\/www\.topografix\.com\/GPX\/1\/1"/);
});

test('toRouteGpxWithMarkers — emits one wpt per marker with lat/lon/name/type', () => {
	const markers = [
		marker({ label: 'Aid 2', lat: 47.37, lng: 8.54, kind: 'aid_station' }),
		marker({ label: 'Cut 1', lat: 47.372, lng: 8.542, kind: 'cutoff' })
	];
	const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, markers);
	assert.equal((xml.match(/<wpt /g) ?? []).length, 2);
	assert.match(xml, /<wpt lat="47\.37" lon="8\.54"><name>Aid 2<\/name><type>aid_station<\/type>/);
	assert.match(xml, /<wpt lat="47\.372" lon="8\.542"><name>Cut 1<\/name><type>cutoff<\/type>/);
});

test('toRouteGpxWithMarkers — cutoff clock + elapsed + services land in desc', () => {
	const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, [
		marker({
			kind: 'aid_station',
			meta: {
				cutoff_clock: '14:30',
				cutoff_elapsed_s: 16200,
				services: ['water', 'food', 'medical']
			}
		})
	]);
	assert.match(
		xml,
		/<desc>Cutoff 14:30 \| Cutoff 4h30m elapsed \| Services: water, food, medical<\/desc>/
	);
});

test('toRouteGpxWithMarkers — elapsed minutes are zero-padded', () => {
	const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, [
		marker({ kind: 'cutoff', meta: { cutoff_elapsed_s: 3660 } })
	]);
	assert.match(xml, /<desc>Cutoff 1h01m elapsed<\/desc>/);
});

test('toRouteGpxWithMarkers — no desc when no cutoff and no services', () => {
	const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, [
		marker({ kind: 'note', meta: {} })
	]);
	assert.ok(!xml.includes('<desc>'), 'no <desc> for an empty meta bag');
});

test('toRouteGpxWithMarkers — maps kind to a Garmin sym, omits for custom/unknown', () => {
	const cases: Array<[string, string | null]> = [
		['aid_station', 'Water Source'],
		['cutoff', 'Danger Area'],
		['crew_access', 'Parking Area'],
		['hazard', 'Danger Area'],
		['note', 'Information'],
		['climb', 'Summit'],
		['custom', null],
		['gas_station', null]
	];
	for (const [kind, sym] of cases) {
		const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, [
			marker({ kind, meta: {} })
		]);
		if (sym === null) {
			assert.ok(!xml.includes('<sym>'), `no <sym> for kind ${kind}`);
		} else {
			assert.match(xml, new RegExp(`<sym>${sym}</sym>`), `kind ${kind} → ${sym}`);
		}
	}
});

test('toRouteGpxWithMarkers — escapes XML metacharacters in name and desc', () => {
	const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, [
		marker({
			label: 'Tom & "Jerry" <aid>',
			kind: 'aid_station',
			meta: { services: ['water & ice'] }
		})
	]);
	assert.ok(!xml.includes('<aid>'), 'angle brackets in label must be escaped');
	assert.match(xml, /<name>Tom &amp; &quot;Jerry&quot; &lt;aid&gt;<\/name>/);
	assert.match(xml, /<desc>Services: water &amp; ice<\/desc>/);
});

test('toRouteGpxWithMarkers — empty marker list still emits the line + zero wpt', () => {
	const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, []);
	assert.equal((xml.match(/<wpt /g) ?? []).length, 0);
	assert.equal((xml.match(/<trkpt /g) ?? []).length, 3);
	assert.match(xml, /<trkpt lat="47\.37" lon="8\.54"><ele>400<\/ele>/);
});

test('toRouteGpxWithMarkers — missing elevation falls back to 0', () => {
	const xml = toRouteGpxWithMarkers('Loop', [[8.54, 47.37]], [], []);
	assert.match(xml, /<ele>0<\/ele>/);
});

test('toRouteGpxWithMarkers — wpt elements precede the trk (GPX 1.1 order)', () => {
	const xml = toRouteGpxWithMarkers('Loop', COORDS_3, ELEVS_3, [
		marker({ kind: 'aid_station', meta: {} })
	]);
	const wptIdx = xml.indexOf('<wpt ');
	const trkIdx = xml.indexOf('<trk>');
	assert.ok(wptIdx > -1 && trkIdx > -1, 'both present');
	assert.ok(wptIdx < trkIdx, 'wpt must come before trk');
});
