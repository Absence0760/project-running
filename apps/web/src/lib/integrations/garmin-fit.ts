/// FIT-file parsing for Garmin imports.
///
/// FIT is a binary protocol Garmin emits for every recorded activity
/// (also Polar / Suunto / Wahoo). We use `fit-file-parser` to decode
/// and project the result onto our Run shape — same fields the GPX /
/// TCX path produces, so downstream rendering doesn't care which
/// source the run came from.
///
/// Single-file `.fit` parsing only; the orchestrator in `garmin-zip.ts`
/// handles bundle (ZIP) uploads on top of this.

import type { TrackPoint } from '../types';

/// Canonical per-lap shape registered in docs/backend/metadata.md § laps. `index`
/// is 1-based; `start_offset_s` is the cumulative duration up to the START
/// of this lap (first lap = 0); `distance_m` / `duration_s` are per-lap
/// deltas, not cumulative. Mirrors the recorder's `lapsToCanonicalJson`.
export interface FitLap {
	index: number;
	start_offset_s: number;
	distance_m: number;
	duration_s: number;
}

interface RawFitLap {
	total_distance?: number;
	total_timer_time?: number;
	total_elapsed_time?: number;
}

/// Project FIT `lap` messages onto the canonical metadata.laps shape.
/// Returns `[]` for a degenerate single-lap file (one lap == the whole
/// activity, i.e. the runner never pressed lap and there were no
/// auto-laps) so we don't write a useless one-element array. Accumulates
/// per-lap durations for `start_offset_s` rather than reading lap
/// timestamps, so the cumulative-BEFORE invariant holds exactly even when
/// the device paused mid-activity.
export function buildCanonicalLaps(laps: RawFitLap[] | undefined | null): FitLap[] {
	if (!laps || laps.length < 2) return [];
	const out: FitLap[] = [];
	let cumulative = 0;
	for (let i = 0; i < laps.length; i++) {
		const lap = laps[i];
		const duration = Math.max(
			0,
			Math.round(lap.total_timer_time ?? lap.total_elapsed_time ?? 0),
		);
		out.push({
			index: i + 1,
			start_offset_s: cumulative,
			distance_m: Math.max(0, lap.total_distance ?? 0),
			duration_s: duration,
		});
		cumulative += duration;
	}
	return out;
}

/// Convert a FIT cadence reading to steps-per-minute. FIT running
/// cadence is per-foot (RPM), so for foot sports the spm a runner
/// recognises is double the reported value; cycling cadence is crank
/// RPM and isn't a step rate, so it's dropped (null). Returns null for
/// missing / non-finite / non-positive readings. Persona-hunt garmin #17.
export function fitCadenceToSpm(raw: unknown, isFootSport: boolean): number | null {
	if (!isFootSport) return null;
	if (typeof raw !== 'number' || !Number.isFinite(raw) || raw <= 0) return null;
	return Math.round(raw * 2);
}

/// Garmin Running Dynamics, projected off a FIT session message. Every
/// field is optional — only the metrics the watch actually recorded are
/// present (a base watch with no HRM-Pro/Run pod carries none of them).
/// Registered in docs/backend/metadata.md § running_dynamics.
export interface RunningDynamics {
	vertical_oscillation_mm?: number;
	gct_ms?: number;
	stride_length_m?: number;
	power_w?: number;
}

interface RawFitSessionDynamics {
	avg_vertical_oscillation?: unknown;
	vertical_oscillation?: unknown;
	avg_stance_time?: unknown;
	stance_time?: unknown;
	avg_step_length?: unknown;
	step_length?: unknown;
	avg_power?: unknown;
	power?: unknown;
}

function finitePositive(v: unknown): number | null {
	return typeof v === 'number' && Number.isFinite(v) && v > 0 ? v : null;
}

/// Project the Running Dynamics fields off a FIT session. Returns null
/// when the session carried none of them, so the caller can omit the key
/// entirely rather than write an empty object. `fit-file-parser` reports
/// vertical oscillation + step length in mm (lengthUnit only rescales
/// position/altitude/distance), stance time in ms, power in W. Step length
/// is converted mm → m to match the rest of the app's metre convention.
/// L/R balance is intentionally not captured: fit-file-parser decodes the
/// session `left_right_balance` field as an enum string ('0' | 'mask' |
/// 'right'), not the numeric percentage, so there is no reliable number to
/// store — adding it back needs a parser that surfaces the raw 0–100 value.
export function buildRunningDynamics(
	session: RawFitSessionDynamics | null | undefined,
): RunningDynamics | null {
	if (!session) return null;
	const out: RunningDynamics = {};
	const vo = finitePositive(session.avg_vertical_oscillation ?? session.vertical_oscillation);
	if (vo != null) out.vertical_oscillation_mm = Math.round(vo * 10) / 10;
	const gct = finitePositive(session.avg_stance_time ?? session.stance_time);
	if (gct != null) out.gct_ms = Math.round(gct);
	const step = finitePositive(session.avg_step_length ?? session.step_length);
	if (step != null) out.stride_length_m = Math.round(step) / 1000;
	const power = finitePositive(session.avg_power ?? session.power);
	if (power != null) out.power_w = Math.round(power);
	return Object.keys(out).length > 0 ? out : null;
}

/// Cross-source dedupe key for a Garmin activity, from its FIT file_id.
/// `garmin:{file_id}` mirrors the `strava:{id}` / `csv:{...}` convention so a
/// re-import of the same activity is caught by the per-user runs.external_id
/// unique index. Returns null when the file had no usable file_id (#18).
export function garminExternalId(fileId: string | null): string | null {
	return fileId ? `garmin:${fileId}` : null;
}

// ---------------------------------------------------------------------------
// Embedded best efforts.
//
// The whole-run distance of a long run misses every canonical PR bracket, so
// a sub-20 5k inside a 30 km long run never reaches `personal_records`. The
// refresher reads the promoted `runs.fastest_{5k,10k,half_marathon,marathon}_s`
// columns (20270325_001; metadata keys before that); the live recorder
// writes them (embedded_bests.dart) but no importer did. Keep the algorithm
// in lockstep with `fastestWindowOf` in
// `apps/mobile_android/lib/run_stats.dart` + `enrichMetadataWithEmbeddedBests`
// in `apps/mobile_android/lib/embedded_bests.dart` (and the Deno twin in
// `apps/backend/supabase/functions/_shared/strava.ts`) so an imported run's
// best matches what a live recording of the same effort would write.
// ---------------------------------------------------------------------------

export type EmbeddedBestColumn =
	| 'fastest_5k_s'
	| 'fastest_10k_s'
	| 'fastest_half_marathon_s'
	| 'fastest_marathon_s';

/// Canonical distances (metres) → runs column. Matches the bracket
/// midpoints the SQL trigger searches (±2 % wide, so 5000 m exactly).
export const EMBEDDED_BEST_DISTANCES: ReadonlyArray<readonly [EmbeddedBestColumn, number]> = [
	['fastest_5k_s', 5000],
	['fastest_10k_s', 10000],
	['fastest_half_marathon_s', 21097.5],
	['fastest_marathon_s', 42195],
];

function embeddedHaversineM(lat1: number, lng1: number, lat2: number, lng2: number): number {
	const r = 6371000;
	const toRad = Math.PI / 180;
	const dLat = (lat2 - lat1) * toRad;
	const dLng = (lng2 - lng1) * toRad;
	const s1 = Math.sin(dLat / 2);
	const s2 = Math.sin(dLng / 2);
	const a = s1 * s1 + Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * s2 * s2;
	return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function pointMs(p: TrackPoint): number | null {
	if (typeof p.ts !== 'string') return null;
	const ms = Date.parse(p.ts);
	return Number.isFinite(ms) ? ms : null;
}

/// Fastest continuous `windowMetres` (whole seconds) anywhere in the track,
/// or null when the track has < 2 points, is shorter than the window, or has
/// no timestamped window. Sliding-window with linear interpolation at the
/// exact distance boundary — the port of Dart's `fastestWindowOf`.
export function fastestWindowSeconds(
	track: readonly TrackPoint[],
	windowMetres: number,
): number | null {
	const n = track.length;
	if (n < 2 || windowMetres <= 0) return null;

	const cum = new Array<number>(n).fill(0);
	for (let i = 1; i < n; i++) {
		cum[i] = cum[i - 1] +
			embeddedHaversineM(track[i - 1].lat, track[i - 1].lng, track[i].lat, track[i].lng);
	}
	if (cum[n - 1] < windowMetres) return null;

	let best: number | null = null;
	let i = 0;
	for (let j = 1; j < n; j++) {
		while (i + 1 < j && cum[j] - cum[i + 1] >= windowMetres) i++;
		if (cum[j] - cum[i] < windowMetres) continue;

		const ti = pointMs(track[i]);
		const tj = pointMs(track[j]);
		if (ti == null || tj == null) continue;

		const segDist = cum[i + 1] - cum[i];
		let startMs: number;
		if (segDist <= 0) {
			startMs = ti;
		} else {
			const ti1 = pointMs(track[i + 1]);
			if (ti1 == null) {
				startMs = ti;
			} else {
				const targetCum = cum[j] - windowMetres;
				const fraction = Math.min(1, Math.max(0, (targetCum - cum[i]) / segDist));
				startMs = ti + Math.round((ti1 - ti) * fraction);
			}
		}

		const windowMs = tj - startMs;
		if (windowMs <= 0) continue;
		if (best == null || windowMs < best) best = windowMs;
	}
	return best == null ? null : Math.round(best / 1000);
}

/// Embedded best-effort seconds for every canonical distance the track is
/// long enough to cover. Returns `{}` (no fake bests) when the track has < 3
/// points or covers no canonical distance; callers pass the result to
/// saveRun's `embedded_bests` so it lands on the promoted runs columns.
export function computeEmbeddedBests(
	track: readonly TrackPoint[],
): Partial<Record<EmbeddedBestColumn, number>> {
	const out: Partial<Record<EmbeddedBestColumn, number>> = {};
	if (!Array.isArray(track) || track.length < 3) return out;
	for (const [key, dist] of EMBEDDED_BEST_DISTANCES) {
		const secs = fastestWindowSeconds(track, dist);
		if (secs != null && secs > 0) out[key] = secs;
	}
	return out;
}

export interface ParsedFitRun {
	/// ISO timestamp of the session start.
	startedAt: string;
	distance_m: number;
	duration_s: number;
	elevation_m: number | null;
	/// Coarsened sport — only the four foot/cycle classes the rest of
	/// the app understands. `null` for sports we explicitly don't
	/// support (swim, hike-with-no-foot-pod, ski, etc.).
	activity_type: 'run' | 'walk' | 'hike' | 'cycle' | null;
	avg_bpm: number | null;
	max_bpm: number | null;
	/// Average running cadence in steps-per-minute (both feet). FIT
	/// reports running cadence per-foot (RPM), so this is doubled for
	/// foot sports; null for cycling (crank RPM is a different metric)
	/// and for files with no cadence. Persona-hunt garmin #17.
	avg_cadence_spm: number | null;
	total_ascent_m: number | null;
	/// Stable per-file identity from the FIT `file_id` message — used
	/// for dedupe. `null` only for malformed files without a file_id.
	garmin_file_id: string | null;
	/// Canonical per-lap deltas from the FIT `lap` messages. Empty when
	/// the file has no real laps (single whole-activity lap).
	laps: FitLap[];
	/// True for treadmill / indoor / virtual sessions — distance is
	/// belt-/estimate-derived, not GPS, so it must not feed VDOT (#16).
	indoor: boolean;
	/// Normalised FIT `sub_sport` (e.g. `trail`, `treadmill`, `track`,
	/// `road`). Preserves the discipline the coarse `activity_type` throws
	/// away — there is no `trail` activity_type. `null` when the file had
	/// no `sub_sport` or only the uninformative `generic`. (persona round-5 F1)
	sub_sport: string | null;
	/// Garmin Running Dynamics off the session, when the watch recorded
	/// them. `null` for files without any of the fields. (persona round-5 F2)
	running_dynamics: RunningDynamics | null;
	/// HR-zone boundaries from the FIT `hr_zone` messages, when the file
	/// carried a full five-zone set. Used to one-time seed the user's
	/// `hr_zones` setting on import. `null` when the file had no zones.
	hr_zones: FitHrZones | null;
	track: TrackPoint[];
	/// Per-point HR for records that carried no GPS fix (indoor / treadmill).
	/// On an outdoor run every record has a fix and its HR rides on the
	/// `track` point, so this is empty; on an indoor run `track` is empty and
	/// the HR lives here instead. The writer uploads it as the
	/// `{user_id}/{run_id}.hr.json.gz` sidecar only when `track` has no bpm, so
	/// the run-detail HR-zone chart works for trackless runs (decisions §116).
	hr_series: { bpm: number; ts?: string }[];
}

/// The five HR-zone upper boundaries, matching the app's
/// `user_settings.prefs.hr_zones` shape. `z1`..`z5` are the upper bpm of
/// zones 1-5; a measured HR at or below `z1` is zone 1, etc.
export interface FitHrZones {
	z1: number;
	z2: number;
	z3: number;
	z4: number;
	z5: number;
}

/// Project the FIT `hr_zone` messages onto the app's 5-cutoff shape.
/// Each FIT `hr_zone` carries a `high_bpm` upper boundary; Garmin emits
/// one per zone (sometimes with a leading resting-zone entry). We take the
/// five highest distinct boundaries in ascending order as z1..z5, so the
/// optional resting-zone-0 entry is dropped. Returns null when fewer than
/// five usable boundaries are present (e.g. the watch had no zones set).
export function buildHrZonesFromFit(
	zones: { high_bpm?: unknown }[] | undefined | null,
): FitHrZones | null {
	if (!zones || zones.length === 0) return null;
	const highs = zones
		.map((z) => (typeof z.high_bpm === 'number' ? z.high_bpm : NaN))
		.filter((n) => Number.isFinite(n) && n >= 60 && n <= 230);
	const uniqAsc = Array.from(new Set(highs)).sort((a, b) => a - b);
	if (uniqAsc.length < 5) return null;
	const last5 = uniqAsc.slice(-5);
	return { z1: last5[0], z2: last5[1], z3: last5[2], z4: last5[3], z5: last5[4] };
}

/// Normalise a FIT `sub_sport` enum value. Lower-cases and drops the
/// uninformative `generic` / `all` placeholders + empties to null so we
/// never persist a meaningless discipline. (persona round-5 F1)
export function normalizeSubSport(raw: unknown): string | null {
	if (typeof raw !== 'string') return null;
	const s = raw.trim().toLowerCase();
	if (!s || s === 'generic' || s === 'all' || s === 'invalid') return null;
	return s;
}

/// Parse a single FIT activity buffer. Returns `null` for files that
/// aren't activity files (workouts, courses, settings, etc.) or that
/// have no usable session data.
///
/// `fit-file-parser` is dynamically imported so the ~200 KB binary
/// decoder is only fetched when a user actually triggers a Garmin
/// import — keeps the rest of the integrations page light.
export async function parseFitBuffer(buf: ArrayBuffer): Promise<ParsedFitRun | null> {
	const { default: FitParser } = await import('fit-file-parser');
	const parser = new FitParser({
		// Match the rest of the codebase: metres + m/s + °C + Pa.
		lengthUnit: 'm',
		speedUnit: 'm/s',
		temperatureUnit: 'celsius',
		pressureUnit: 'pascal',
		// Flat lists are easier to walk than the nested cascade form.
		mode: 'list',
		// Keep parsing past minor protocol mismatches so we recover the
		// session even if a developer-data block is malformed.
		force: true,
	});

	const data = await parser.parseAsync(buf);

	const session = data.sessions?.[0];
	if (!session || !session.start_time) return null;

	const records = data.records ?? [];

	const track: TrackPoint[] = [];
	const hrSeries: { bpm: number; ts?: string }[] = [];
	for (const r of records) {
		// FIT positions arrive in semicircles by default but the parser
		// converts them to degrees once `lengthUnit` is set.
		const hasFix =
			typeof r.position_lat === 'number' &&
			typeof r.position_long === 'number' &&
			Number.isFinite(r.position_lat) &&
			Number.isFinite(r.position_long);
		const validHr =
			typeof r.heart_rate === 'number' && r.heart_rate >= 30 && r.heart_rate <= 230;
		const ts = (r as { timestamp?: string }).timestamp;
		if (hasFix) {
			const tp: TrackPoint = {
				lat: r.position_lat as number,
				lng: r.position_long as number,
			};
			if (typeof r.altitude === 'number' && Number.isFinite(r.altitude)) {
				tp.ele = r.altitude;
			}
			if (typeof ts === 'string') tp.ts = ts;
			if (validHr) tp.bpm = r.heart_rate as number;
			track.push(tp);
		} else if (validHr) {
			// Indoor / treadmill record: HR but no GPS. Garmin emits these on
			// every belt session. Collect the HR so the run-detail zone chart
			// has a series even though `track` will be empty.
			const sample: { bpm: number; ts?: string } = { bpm: r.heart_rate as number };
			if (typeof ts === 'string') sample.ts = ts;
			hrSeries.push(sample);
		}
	}

	const sport = (session.sport ?? '').toLowerCase();
	const rawSubSport = (session as { sub_sport?: string }).sub_sport;
	const subSport = (rawSubSport ?? '').toLowerCase();
	const indoor =
		subSport.includes('treadmill') ||
		subSport.includes('indoor') ||
		subSport.includes('virtual') ||
		sport.includes('treadmill');
	let activityType: ParsedFitRun['activity_type'] = null;
	if (sport === 'running' || subSport.includes('run')) activityType = 'run';
	else if (sport === 'walking' || subSport.includes('walk')) activityType = 'walk';
	else if (sport === 'hiking' || subSport.includes('hike')) activityType = 'hike';
	else if (sport === 'cycling' || subSport.includes('cycl') || subSport.includes('bike'))
		activityType = 'cycle';

	const isFoot =
		activityType === 'run' || activityType === 'walk' || activityType === 'hike';
	const avgCadenceSpm = fitCadenceToSpm(
		(session as { avg_running_cadence?: number; avg_cadence?: number }).avg_running_cadence ??
			(session as { avg_cadence?: number }).avg_cadence,
		isFoot,
	);

	const fileIdEntry = data.file_ids?.[0];
	// fit-file-parser decodes FIT `date_time` fields (incl. file_id's
	// time_created) into a JS Date. Template-stringifying a Date yields a
	// localised, timezone-dependent string ("…GMT-0400 (Eastern Daylight
	// Time)"), so the same activity imported in two timezones produced two
	// different external_ids and the per-user runs.external_id unique index
	// never caught the re-import. Coerce the Date back to epoch seconds for
	// a stable, timezone-independent dedupe key.
	const rawTimeCreated = (fileIdEntry as { time_created?: unknown } | undefined)?.time_created;
	const timeKey =
		rawTimeCreated instanceof Date
			? Math.floor(rawTimeCreated.getTime() / 1000)
			: (rawTimeCreated ?? '');
	const garminFileId = fileIdEntry
		? `${timeKey}-${fileIdEntry.serial_number ?? ''}`
		: null;

	return {
		startedAt: new Date(session.start_time).toISOString(),
		distance_m: Math.max(0, Math.round(session.total_distance ?? 0)),
		duration_s: Math.max(
			0,
			Math.round(session.total_timer_time ?? session.total_elapsed_time ?? 0),
		),
		elevation_m:
			typeof session.total_ascent === 'number' ? Math.round(session.total_ascent) : null,
		activity_type: activityType,
		avg_bpm:
			typeof session.avg_heart_rate === 'number' && session.avg_heart_rate > 0
				? Math.round(session.avg_heart_rate)
				: null,
		max_bpm:
			typeof session.max_heart_rate === 'number' && session.max_heart_rate > 0
				? Math.round(session.max_heart_rate)
				: null,
		avg_cadence_spm: avgCadenceSpm,
		total_ascent_m:
			typeof session.total_ascent === 'number' ? Math.round(session.total_ascent) : null,
		garmin_file_id: garminFileId && garminFileId !== '-' ? garminFileId : null,
		laps: buildCanonicalLaps(data.laps as RawFitLap[] | undefined),
		indoor,
		sub_sport: normalizeSubSport(rawSubSport),
		running_dynamics: buildRunningDynamics(session as RawFitSessionDynamics),
		hr_zones: buildHrZonesFromFit(
			(data as { hr_zone?: { high_bpm?: unknown }[] }).hr_zone,
		),
		track,
		hr_series: hrSeries,
	};
}
