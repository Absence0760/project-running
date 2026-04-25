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

import type { TrackPoint } from './types';

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
	total_ascent_m: number | null;
	/// Stable per-file identity from the FIT `file_id` message — used
	/// for dedupe. `null` only for malformed files without a file_id.
	garmin_file_id: string | null;
	track: TrackPoint[];
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
	for (const r of records) {
		// FIT positions arrive in semicircles by default but the parser
		// converts them to degrees once `lengthUnit` is set. Skip
		// records without a fix — Garmin emits indoor records with no
		// lat/lng but with HR / pace.
		if (
			typeof r.position_lat === 'number' &&
			typeof r.position_long === 'number' &&
			Number.isFinite(r.position_lat) &&
			Number.isFinite(r.position_long)
		) {
			const tp: TrackPoint = {
				lat: r.position_lat,
				lng: r.position_long,
			};
			if (typeof r.altitude === 'number' && Number.isFinite(r.altitude)) {
				tp.ele = r.altitude;
			}
			const ts = (r as { timestamp?: string }).timestamp;
			if (typeof ts === 'string') tp.ts = ts;
			if (
				typeof r.heart_rate === 'number' &&
				r.heart_rate >= 30 &&
				r.heart_rate <= 230
			) {
				tp.bpm = r.heart_rate;
			}
			track.push(tp);
		}
	}

	const sport = (session.sport ?? '').toLowerCase();
	const subSport = ((session as { sub_sport?: string }).sub_sport ?? '').toLowerCase();
	let activityType: ParsedFitRun['activity_type'] = null;
	if (sport === 'running' || subSport.includes('run')) activityType = 'run';
	else if (sport === 'walking' || subSport.includes('walk')) activityType = 'walk';
	else if (sport === 'hiking' || subSport.includes('hike')) activityType = 'hike';
	else if (sport === 'cycling' || subSport.includes('cycl') || subSport.includes('bike'))
		activityType = 'cycle';

	const fileIdEntry = data.file_ids?.[0];
	const garminFileId = fileIdEntry
		? `${fileIdEntry.time_created ?? ''}-${fileIdEntry.serial_number ?? ''}`
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
		total_ascent_m:
			typeof session.total_ascent === 'number' ? Math.round(session.total_ascent) : null,
		garmin_file_id: garminFileId && garminFileId !== '-' ? garminFileId : null,
		track,
	};
}
