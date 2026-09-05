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
	CSV_OMIT,
	csvRow,
	GPX_MANIFEST_OMIT,
	hrCoverageCell,
	omitKeys,
	type RenderRunRow,
	type RenderTrackPoint,
	RUNS_JSON_OMIT,
	stringy,
	xmlEscape,
} from './render.ts';

const REF: RenderRunRow = {
	id: '11111111-1111-1111-1111-111111111111',
	user_id: '22222222-2222-2222-2222-222222222222',
	started_at: '2026-05-01T06:00:00+00:00',
	concluded_at: null,
	duration_s: 3600,
	distance_m: 10000,
	elevation_gain_m: null,
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
	race_listing_id: null,
	fastest_5k_s: null,
	fastest_10k_s: null,
	fastest_half_marathon_s: null,
	fastest_marathon_s: null,
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
	assertEquals(CSV_COLS.length, 26);
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

Deno.test('the seven columns that reached no format now reach the CSV', () => {
	// Four of them stopped being exported the day migration 20270325_001
	// promoted them out of `runs.metadata` and stripped the keys from the bag
	// in the same statement; the other three were never selected at all
	// (decisions § 1171). `manifest.json` cannot show this — its completeness
	// contract is row counts, and every row was present.
	const row = csvFields(csvRow({
		...REF,
		concluded_at: '2026-05-01T07:02:11+00:00',
		elevation_gain_m: 128.5,
		race_listing_id: '33333333-3333-3333-3333-333333333333',
		fastest_5k_s: 1320,
		fastest_10k_s: 2790,
		fastest_half_marathon_s: 6180,
		fastest_marathon_s: null,
	}));
	const at = (col: string) => row[CSV_COLS.indexOf(col)];
	assertEquals(at('concluded_at'), '2026-05-01T07:02:11+00:00');
	assertEquals(at('elevation_gain_m'), '128.5');
	assertEquals(at('race_listing_id'), '33333333-3333-3333-3333-333333333333');
	assertEquals(at('fastest_5k_s'), '1320');
	assertEquals(at('fastest_10k_s'), '2790');
	assertEquals(at('fastest_half_marathon_s'), '6180');
	// A run that set no marathon PR states nothing rather than a zero.
	assertEquals(at('fastest_marathon_s'), '');
	assertEquals(row.length, CSV_COLS.length);
});

Deno.test('the CSV names every runs column except the three it declares', () => {
	// The rule the header is derived from, asserted here rather than left to
	// the reader: CSV_COLS is the table minus CSV_OMIT, plus the five
	// `metadata` keys it names outright. The Go worker's own guard is what
	// holds the two rails to the same list.
	const metadataCells = ['title', 'avg_bpm', 'hr_coverage', 'steps', 'elevation_m'];
	const columns = Object.keys(REF).sort();
	const carried = CSV_COLS.filter((c) => !metadataCells.includes(c)).sort();
	assertEquals(carried.concat([...CSV_OMIT]).sort(), columns);
});

Deno.test('the runs.json projections are omissions, so a new column is exported by default', () => {
	const backup = omitKeys(REF as unknown as Record<string, unknown>, RUNS_JSON_OMIT);
	const manifest = omitKeys(REF as unknown as Record<string, unknown>, GPX_MANIFEST_OMIT);
	assertEquals(
		Object.keys(backup).sort().concat([...RUNS_JSON_OMIT]).sort(),
		Object.keys(REF).sort(),
	);
	assertEquals(
		Object.keys(manifest).sort().concat([...GPX_MANIFEST_OMIT]).sort(),
		Object.keys(REF).sort(),
	);
	// The archive is re-homeable, so neither carries the subject's own id;
	// the manifest additionally drops the two Storage paths, which the GPX
	// files beside it make redundant.
	assert(!('user_id' in backup));
	assert(!('track_url' in manifest));
	assert(!('hr_series_url' in manifest));
	// And the backup keeps them, because a restore needs the path.
	assertEquals(backup.track_url, REF.track_url);
	assertEquals(backup.fastest_5k_s, REF.fastest_5k_s);
	assertEquals(manifest.fastest_5k_s, REF.fastest_5k_s);
});

Deno.test('hr_coverage sits beside the column it qualifies', () => {
	// Adjacency is the point of the column, not a cosmetic. `avg_bpm` is a
	// mean over a share of the run the recorder measured and the CSV never
	// stated; a reader scanning a spreadsheet has to see the two together or
	// the qualification does not reach them (decisions § 1134).
	assertEquals(CSV_COLS.indexOf('hr_coverage'), CSV_COLS.indexOf('avg_bpm') + 1);
});

Deno.test('the three heart-rate shapes are distinguishable in the CSV', () => {
	const cell = (r: RenderRunRow, col: string) => csvFields(csvRow(r))[CSV_COLS.indexOf(col)];
	const run = (metadata: Record<string, unknown>) => ({ ...REF, metadata });

	// 1. Full coverage: the average is the run's average, and the column
	//    says the sensor covered all of it.
	const full = run({ avg_bpm: 142, hr_coverage: 1 });
	assertEquals(cell(full, 'avg_bpm'), '142');
	assertEquals(cell(full, 'hr_coverage'), '1');

	// 2. Partial coverage: the same 142 bpm, measured over 51 % of the run.
	//    Before § 1134 this exported identically to the row above.
	const partial = run({ avg_bpm: 142, hr_coverage: 0.51 });
	assertEquals(cell(partial, 'avg_bpm'), '142');
	assertEquals(cell(partial, 'hr_coverage'), '0.51');
	assert(cell(partial, 'hr_coverage') !== cell(full, 'hr_coverage'));

	// 3. Suppressed average: the Wear recorder drops `avg_bpm` below 0.5
	//    coverage (§ 1083), so the average is absent BECAUSE it was measured
	//    badly — not because the runner wore no strap. The strap-less run is
	//    the contrast that makes the claim mean anything, and the two used to
	//    export as the same empty cell.
	const suppressed = run({ hr_coverage: 0.12 });
	const noStrap = run({});
	assertEquals(cell(suppressed, 'avg_bpm'), '');
	assertEquals(cell(noStrap, 'avg_bpm'), '');
	assertEquals(cell(suppressed, 'hr_coverage'), '0.12');
	assertEquals(cell(noStrap, 'hr_coverage'), '');

	// A sensor enabled that delivered nothing is a MEASUREMENT of zero, and
	// must not collapse onto the strap-less run's empty cell either.
	assertEquals(cell(run({ hr_coverage: 0 }), 'hr_coverage'), '0');
});

Deno.test('hrCoverageCell states only a fraction it can vouch for', () => {
	// The writer's contract is 0..1 (decisions § 1083). A value outside it is
	// one this build cannot interpret, and a consumer reading `85` out of a
	// column documented as a fraction computes 8500 % — the same refusal the
	// page makes in § 1088.
	assertEquals(hrCoverageCell(0), '0');
	assertEquals(hrCoverageCell(0.5), '0.5');
	assertEquals(hrCoverageCell(1), '1');
	assertEquals(hrCoverageCell(1.4), '');
	assertEquals(hrCoverageCell(85), '');
	assertEquals(hrCoverageCell(-0.1), '');
	assertEquals(hrCoverageCell(Number.NaN), '');
	assertEquals(hrCoverageCell(Number.POSITIVE_INFINITY), '');
	assertEquals(hrCoverageCell('0.5'), '');
	assertEquals(hrCoverageCell(null), '');
	assertEquals(hrCoverageCell(undefined), '');
});

Deno.test('a refused coverage is withheld from its column, not from the export', () => {
	// Grading the column withholds nothing from the subject: Art 20 is
	// satisfied by the `metadata` column, which carries the stored bag
	// verbatim. The column carries what its header promises; the bag carries
	// what the row holds.
	const row = csvFields(csvRow({ ...REF, metadata: { hr_coverage: 85 } }));
	assertEquals(row[CSV_COLS.indexOf('hr_coverage')], '');
	assertEquals(JSON.parse(row[CSV_COLS.indexOf('metadata')]).hr_coverage, 85);
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
