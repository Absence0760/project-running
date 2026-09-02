/// The two text renderers the Art 20 archive is made of, and the two path
/// assertions that gate its service-role downloader.
///
/// None of this had a behavioural test: the four helpers lived inside
/// `index.ts`, which cannot be imported (it runs `Deno.serve`), so
/// `wiring.test.ts` could only grep their call sites as text. The GPX
/// renderer in particular reads a track that is `JSON.parse` of a blob the
/// subject uploaded, with no schema anywhere between the two — and it wrote
/// `lat` and `lng` straight into a quoted XML attribute.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/export-data/render.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	buildGpx,
	canonicalHrUrl,
	canonicalTrackUrl,
	CSV_COLS,
	csvEscape,
	csvRow,
	type RenderRunRow,
	type RenderTrackPoint,
	stringy,
	xmlEscape,
} from './render.ts';

const REF: RenderRunRow = {
	id: '11111111-1111-1111-1111-111111111111',
	user_id: '22222222-2222-2222-2222-222222222222',
	started_at: '2026-05-01T06:00:00+00:00',
	duration_s: 3600,
	distance_m: 10000,
	source: 'manual',
	activity_type: 'run',
	is_dnf: false,
	external_id: null,
	metadata: { title: 'Morning run' },
	track_url: '22222222-2222-2222-2222-222222222222/11111111-1111-1111-1111-111111111111.json.gz',
	hr_series_url:
		'22222222-2222-2222-2222-222222222222/11111111-1111-1111-1111-111111111111.hr.json.gz',
	is_public: false,
	event_id: null,
	route_id: null,
	created_at: '2026-05-01T07:00:00+00:00',
	updated_at: '2026-05-01T07:00:00+00:00',
};

const GPX_REF = {
	id: REF.id,
	startedAt: REF.started_at,
	title: 'Morning run',
	key: REF.track_url!,
};

/// RFC 4180 field split, so an assertion about column COUNT is not fooled by
/// a comma the escaper legitimately quoted.
function csvFields(line: string): string[] {
	const out: string[] = [];
	let field = '';
	let quoted = false;
	for (let i = 0; i < line.length; i++) {
		const c = line[i];
		if (quoted) {
			if (c === '"') {
				if (line[i + 1] === '"') {
					field += '"';
					i++;
				} else quoted = false;
			} else field += c;
		} else if (c === '"') quoted = true;
		else if (c === ',') {
			out.push(field);
			field = '';
		} else field += c;
	}
	out.push(field);
	return out;
}

Deno.test('csvRow emits exactly one value per declared column', () => {
	// A column added to CSV_COLS without a matching value in csvRow shifts
	// every later field by one for the whole export, silently — a consumer
	// reads `is_public` out of the `external_id` slot and nothing errors.
	assertEquals(CSV_COLS.length, 18);
	assertEquals(csvFields(csvRow(REF)).length, CSV_COLS.length);
});

Deno.test('csvRow puts each value under the header its name promises', () => {
	const row = csvFields(csvRow(REF));
	const at = (col: string) => row[CSV_COLS.indexOf(col)];
	assertEquals(at('id'), REF.id);
	assertEquals(at('started_at'), REF.started_at);
	assertEquals(at('distance_m'), '10000');
	assertEquals(at('duration_s'), '3600');
	assertEquals(at('source'), 'manual');
	assertEquals(at('activity_type'), 'run');
	assertEquals(at('is_dnf'), 'false');
	assertEquals(at('title'), 'Morning run');
	assertEquals(at('is_public'), 'false');
	assertEquals(at('created_at'), REF.created_at);
	assertEquals(at('updated_at'), REF.updated_at);
	// The Storage path is deliberately absent from the CSV: it is a key into
	// the owner's folder that any live session JWT could then fetch directly.
	assert(!CSV_COLS.includes('track_url'));
	assert(!csvRow(REF).includes('.json.gz'));
});

Deno.test('a title carrying the delimiter set survives the round trip', () => {
	// The title is free text the runner typed. A bare comma would end the
	// field, a bare quote would open one, and a newline would end the record
	// — turning the rest of the run into a row of its own.
	const hostile = 'Long run, "hard", 10k\nnext line\r';
	const row = csvFields(csvRow({ ...REF, metadata: { title: hostile } }));
	assertEquals(row.length, CSV_COLS.length);
	assertEquals(row[CSV_COLS.indexOf('title')], hostile);
	// And the metadata column carries the same text as JSON, still one field.
	assertEquals(JSON.parse(row[CSV_COLS.indexOf('metadata')]).title, hostile);
});

Deno.test('csvEscape quotes exactly the four characters that need it', () => {
	assertEquals(csvEscape(''), '');
	assertEquals(csvEscape('plain'), 'plain');
	assertEquals(csvEscape('a,b'), '"a,b"');
	assertEquals(csvEscape('a"b'), '"a""b"');
	assertEquals(csvEscape('a\nb'), '"a\nb"');
	assertEquals(csvEscape('a\rb'), '"a\rb"');
	// Not quoted, so the escape stays minimal: a semicolon, a tab and a
	// leading space are ordinary content in RFC 4180.
	assertEquals(csvEscape('a;b\t c'), 'a;b\t c');
});

Deno.test('stringy renders each metadata type once, and absence as empty', () => {
	assertEquals(stringy(null), '');
	assertEquals(stringy(undefined), '');
	assertEquals(stringy('x'), 'x');
	assertEquals(stringy(7), '7');
	assertEquals(stringy(false), 'false');
	assertEquals(stringy({ a: 1 }), '{"a":1}');
	assertEquals(stringy([1, 2]), '[1,2]');
});

Deno.test('xmlEscape covers all five predefined entities', () => {
	assertEquals(xmlEscape(`&<>"'`), '&amp;&lt;&gt;&quot;&apos;');
	// Ampersand first, or the escapes escape each other.
	assertEquals(xmlEscape('&lt;'), '&amp;lt;');
	assertEquals(xmlEscape('plain'), 'plain');
});

Deno.test('buildGpx escapes every text field it interpolates, not only the title', () => {
	// The Go twin (`buildGpxDoc` in internal/dataexport/server.go) escapes the
	// title, the start time AND each point's timestamp. This one escaped the
	// title alone, and `startedAt` / `ts` are read from a row and a blob.
	const gpx = buildGpx(
		{ ...GPX_REF, title: 'Run <b>&"one"</b>', startedAt: '2026-05-01T06:00:00Z"><evil' },
		[{ lat: 1, lng: 2, ts: '2026-05-01T06:00:01Z</time><evil' }],
	);
	assert(!gpx.includes('<b>'), 'the title reached the document as markup');
	assert(!gpx.includes('><evil'), 'an unescaped field closed a tag');
	assert(gpx.includes('&lt;b&gt;&amp;&quot;one&quot;&lt;/b&gt;'), 'the title is not escaped');
	assert(gpx.includes('&quot;&gt;&lt;evil'), 'the start time is not escaped');
	assert(gpx.includes('&lt;/time&gt;&lt;evil'), 'the point timestamp is not escaped');
});

Deno.test('buildGpx never writes a non-numeric coordinate into an attribute', () => {
	// The track is JSON.parse of a blob, so `lat` carries whatever type the
	// writer put there. A string closes the quoted attribute and everything
	// after it is markup. The Go twin cannot reach this state: its decode
	// types the field as float64.
	const track = [
		{ lat: 51.5, lng: -0.12 },
		{ lat: '1" onload="x', lng: 0 },
		{ lat: 2, lng: NaN },
		{ lat: 3, lng: 4 },
	] as unknown as RenderTrackPoint[];
	const gpx = buildGpx(GPX_REF, track);
	assert(!gpx.includes('onload'), 'a string coordinate reached the attribute');
	assert(!gpx.includes('NaN'), 'a non-finite coordinate reached the attribute');
	// The two placeable points are kept — dropping the unplaceable ones must
	// not cost the rest of the track.
	assertEquals(gpx.match(/<trkpt /g)?.length, 2);
	assert(gpx.includes('<trkpt lat="51.5" lon="-0.12">'));
	assert(gpx.includes('<trkpt lat="3" lon="4">'));
});

Deno.test('buildGpx omits an elevation or heart rate it cannot render as a number', () => {
	const gpx = buildGpx(GPX_REF, [
		{ lat: 1, lng: 2, ele: 100, bpm: 150 },
		{ lat: 1, lng: 2, ele: 'high', bpm: '</hr><evil' } as unknown as RenderTrackPoint,
		{ lat: 1, lng: 2, ele: Infinity, bpm: 0 },
	]);
	assertEquals(gpx.match(/<ele>/g)?.length, 1);
	assert(gpx.includes('<ele>100</ele>'));
	assertEquals(gpx.match(/<gpxtpx:hr>/g)?.length, 1);
	assert(gpx.includes('<gpxtpx:hr>150</gpxtpx:hr>'));
	assert(!gpx.includes('evil'));
	assert(!gpx.includes('Infinity'));
});

Deno.test('buildGpx writes heart rate as the integer the element requires', () => {
	// GPX's TrackPointExtension hr is an integer; the Go twin formats it with
	// %d. A fractional bpm from a resampled series used to be written whole.
	const gpx = buildGpx(GPX_REF, [{ lat: 1, lng: 2, bpm: 148.6 }]);
	assert(gpx.includes('<gpxtpx:hr>148</gpxtpx:hr>'), gpx);
});

Deno.test('buildGpx frames a well-formed document around an empty track', () => {
	const gpx = buildGpx(GPX_REF, []);
	assert(gpx.startsWith('<?xml version="1.0" encoding="UTF-8"?>\n'));
	assert(gpx.includes('<gpx version="1.1" creator="Runonward"'));
	assert(gpx.includes('<trkseg>') && gpx.includes('</trkseg>'));
	assert(gpx.trimEnd().endsWith('</gpx>'));
	assertEquals(gpx.match(/<trkpt /g), null);
	// Opened and closed exactly once each, so a renderer that stopped closing
	// a tag produces a file no loader accepts and this notices.
	for (const tag of ['gpx', 'trk', 'trkseg', 'metadata']) {
		assertEquals(gpx.match(new RegExp(`</${tag}>`, 'g'))?.length, 1, tag);
	}
});

Deno.test('canonicalTrackUrl admits only the exact owner-scoped path', () => {
	assertEquals(canonicalTrackUrl(REF), REF.track_url);
	assertEquals(canonicalTrackUrl({ ...REF, track_url: null }), null);
	// Every near miss a corrupt or legacy row could carry. Each would
	// otherwise be handed to a service-role download that bypasses RLS.
	for (
		const bad of [
			`${REF.user_id}/${REF.id}.json.gz.bak`,
			`x/${REF.user_id}/${REF.id}.json.gz`,
			`${REF.user_id}/../${REF.id}.json.gz`,
			`33333333-3333-3333-3333-333333333333/${REF.id}.json.gz`,
			`${REF.user_id}/${REF.id}.hr.json.gz`,
			`${REF.user_id}/${REF.id}.json`,
			` ${REF.user_id}/${REF.id}.json.gz`,
		]
	) {
		assertEquals(canonicalTrackUrl({ ...REF, track_url: bad }), null, bad);
	}
});

Deno.test('canonicalHrUrl admits only the exact hr path, not the track one', () => {
	assertEquals(canonicalHrUrl(REF), REF.hr_series_url);
	assertEquals(canonicalHrUrl({ ...REF, hr_series_url: null }), null);
	// The two suffixes must not be interchangeable, or the hr sweep downloads
	// the track and stores it under `hr/`.
	assertEquals(canonicalHrUrl({ ...REF, hr_series_url: REF.track_url }), null);
	assertEquals(canonicalTrackUrl({ ...REF, track_url: REF.hr_series_url }), null);
});
