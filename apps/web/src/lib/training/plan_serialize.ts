/**
 * Plan import / export — a Markdown (and JSON) round-trip for training
 * plans. Two use cases:
 *
 *  1. Export your plan to share / archive / hand to a coach.
 *  2. Paste a plan (from a coach, a book, or a previous export) and have
 *     it parsed into weeks + workouts ready to persist.
 *
 * The Markdown shape is a small header block + one table row per
 * workout, keyed by week number + date. It's deliberately
 * human-editable: a coach can paste a hand-built table and it parses,
 * and an exported plan re-imports to the same workouts (the round-trip
 * the tests pin). Pure — no Supabase / DOM.
 *
 * Lossy by design on import: pace tolerance, structured-interval JSON,
 * and duration-based steps aren't represented in the table, so a parsed
 * plan carries distance + pace + notes per workout and nulls the rest.
 * Phase + weekly volume are *recomputed* on import (phase from week
 * position, volume from the summed distances) rather than trusted from
 * the text.
 */

import { GOAL_DISTANCES_M, phaseFor } from './training';
import type { GeneratedPlan, GoalEvent, PlanPhase, WorkoutKind } from './training';

const METRES_PER_MILE = 1609.344;

export const WORKOUT_KINDS: readonly WorkoutKind[] = [
	'easy',
	'long',
	'recovery',
	'tempo',
	'interval',
	'marathon_pace',
	'walk_run',
	'race',
	'rest',
];

const GOAL_EVENTS: readonly GoalEvent[] = [
	'distance_5k',
	'distance_10k',
	'distance_half',
	'distance_full',
	'custom',
];

/// Minimal per-workout shape the exporter needs. Callers flatten their
/// weeks + workouts (DB rows or a GeneratedPlan) into this.
export interface ExportWorkout {
	week_index: number; // 0-based
	scheduled_date: string; // ISO YYYY-MM-DD
	kind: string;
	target_distance_m: number | null;
	target_pace_sec_per_km: number | null;
	notes: string | null;
}

export interface ExportPlan {
	name: string;
	goalEvent: string;
	goalDistanceM: number;
	goalTimeSec: number | null;
	startDate: string;
	workouts: ExportWorkout[];
}

/// A parsed plan, ready to hand to `createTrainingPlan`.
export interface ParsedPlan {
	name: string;
	goalEvent: GoalEvent;
	goalDistanceM: number;
	goalTimeSec: number | null;
	startDate: string;
	generated: GeneratedPlan;
}

function fmtKmCell(metres: number | null): string {
	if (metres == null || metres <= 0) return '';
	return `${(metres / 1000).toFixed(2)} km`;
}

function fmtPaceCell(secPerKm: number | null): string {
	if (secPerKm == null || secPerKm <= 0) return '';
	const m = Math.floor(secPerKm / 60);
	const s = Math.round(secPerKm % 60);
	return `${m}:${String(s).padStart(2, '0')}`;
}

function fmtHmsCell(sec: number | null): string {
	if (sec == null || sec <= 0) return '';
	const h = Math.floor(sec / 3600);
	const m = Math.floor((sec % 3600) / 60);
	const s = Math.round(sec % 60);
	return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

/// Notes can't contain a raw pipe (it would break the table) or a
/// newline; collapse both so a round-trip stays on one row.
function sanitizeCell(s: string | null): string {
	if (!s) return '';
	return s.replace(/\|/g, '/').replace(/\s*\n\s*/g, ' ').trim();
}

export function planToMarkdown(plan: ExportPlan): string {
	const lines: string[] = [];
	lines.push(`# ${sanitizeCell(plan.name) || 'Training plan'}`);
	lines.push('');
	lines.push(`- Goal event: ${plan.goalEvent}`);
	lines.push(`- Goal distance: ${(plan.goalDistanceM / 1000).toFixed(2)} km`);
	if (plan.goalTimeSec != null && plan.goalTimeSec > 0) {
		lines.push(`- Goal time: ${fmtHmsCell(plan.goalTimeSec)}`);
	}
	lines.push(`- Start date: ${plan.startDate}`);
	lines.push('');
	lines.push('| Week | Date | Type | Distance | Pace | Notes |');
	lines.push('| --- | --- | --- | --- | --- | --- |');
	const sorted = [...plan.workouts].sort((a, b) =>
		a.scheduled_date < b.scheduled_date ? -1 : a.scheduled_date > b.scheduled_date ? 1 : 0,
	);
	for (const w of sorted) {
		lines.push(
			`| ${w.week_index + 1} | ${w.scheduled_date} | ${w.kind} | ${fmtKmCell(
				w.target_distance_m,
			)} | ${fmtPaceCell(w.target_pace_sec_per_km)} | ${sanitizeCell(w.notes)} |`,
		);
	}
	return lines.join('\n') + '\n';
}

export function planToJson(plan: ExportPlan): string {
	return JSON.stringify(plan, null, 2);
}

class PlanParseError extends Error {}

function parseDistanceCell(cell: string): number | null {
	const t = cell.trim();
	if (!t) return null;
	const m = t.match(/^([\d.]+)\s*(km|mi|m)?$/i);
	if (!m) throw new PlanParseError(`Couldn't read distance "${cell}".`);
	const num = parseFloat(m[1]);
	if (Number.isNaN(num)) throw new PlanParseError(`Couldn't read distance "${cell}".`);
	const unit = (m[2] ?? 'km').toLowerCase();
	if (unit === 'mi') return num * METRES_PER_MILE;
	if (unit === 'm') return num;
	return num * 1000;
}

function parsePaceCell(cell: string): number | null {
	const t = cell.trim();
	if (!t) return null;
	const m = t.match(/^(\d{1,2}):(\d{2})$/);
	if (!m) throw new PlanParseError(`Couldn't read pace "${cell}" — use m:ss.`);
	return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
}

function parseHms(t: string): number | null {
	const trimmed = t.trim();
	if (!trimmed) return null;
	const parts = trimmed.split(':').map((p) => parseInt(p, 10));
	if (parts.some((p) => Number.isNaN(p))) return null;
	if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
	if (parts.length === 2) return parts[0] * 60 + parts[1];
	return null;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

interface ParsedRow {
	weekIndex: number;
	scheduled_date: string;
	kind: WorkoutKind;
	target_distance_m: number | null;
	target_pace_sec_per_km: number | null;
	notes: string | null;
}

function isSeparatorRow(cells: string[]): boolean {
	return cells.every((c) => /^:?-{2,}:?$/.test(c.trim()) || c.trim() === '');
}

/// Parse a Markdown export (or a hand-written table in the same shape)
/// into a plan ready for `createTrainingPlan`. Throws a readable
/// Error on malformed input so the UI can surface it.
export function parsePlanMarkdown(text: string): ParsedPlan {
	const rawLines = text.split('\n');
	let name = '';
	let goalEventToken: string | null = null;
	let goalDistanceM: number | null = null;
	let goalTimeSec: number | null = null;
	let startDate: string | null = null;
	const rows: ParsedRow[] = [];
	let sawHeaderRow = false;

	for (const raw of rawLines) {
		const line = raw.trim();
		if (!line) continue;
		if (line.startsWith('# ')) {
			if (!name) name = line.slice(2).trim();
			continue;
		}
		if (line.startsWith('- ')) {
			const body = line.slice(2);
			const colon = body.indexOf(':');
			if (colon === -1) continue;
			const key = body.slice(0, colon).trim().toLowerCase();
			const val = body.slice(colon + 1).trim();
			if (key === 'goal event') goalEventToken = val;
			else if (key === 'goal distance') goalDistanceM = parseDistanceCell(val);
			else if (key === 'goal time') goalTimeSec = parseHms(val);
			else if (key === 'start date') startDate = val;
			continue;
		}
		if (line.startsWith('|')) {
			const cells = line
				.split('|')
				.slice(1, -1)
				.map((c) => c.trim());
			if (cells.length < 6) continue;
			if (isSeparatorRow(cells)) continue;
			// Header row (the `Week | Date | …` titles) — skip once.
			if (!sawHeaderRow && /week/i.test(cells[0]) && /date/i.test(cells[1])) {
				sawHeaderRow = true;
				continue;
			}
			const [weekCell, dateCell, kindCell, distCell, paceCell, ...noteCells] = cells;
			const weekNum = parseInt(weekCell, 10);
			if (Number.isNaN(weekNum) || weekNum < 1) {
				throw new PlanParseError(`Bad week number "${weekCell}".`);
			}
			if (!ISO_DATE.test(dateCell)) {
				throw new PlanParseError(`Bad date "${dateCell}" — use YYYY-MM-DD.`);
			}
			const kind = kindCell.trim().toLowerCase() as WorkoutKind;
			if (!WORKOUT_KINDS.includes(kind)) {
				throw new PlanParseError(`Unknown workout type "${kindCell}".`);
			}
			rows.push({
				weekIndex: weekNum - 1,
				scheduled_date: dateCell,
				kind,
				target_distance_m: parseDistanceCell(distCell),
				target_pace_sec_per_km: parsePaceCell(paceCell),
				notes: noteCells.join('|').trim() || null,
			});
		}
	}

	if (rows.length === 0) {
		throw new PlanParseError('No workout rows found. Expected a | Week | Date | … | table.');
	}

	rows.sort((a, b) => (a.scheduled_date < b.scheduled_date ? -1 : a.scheduled_date > b.scheduled_date ? 1 : 0));

	const totalWeeks = Math.max(...rows.map((r) => r.weekIndex)) + 1;
	const byWeek = new Map<number, ParsedRow[]>();
	for (const r of rows) {
		const list = byWeek.get(r.weekIndex) ?? [];
		list.push(r);
		byWeek.set(r.weekIndex, list);
	}

	const weeks = [...byWeek.keys()]
		.sort((a, b) => a - b)
		.map((weekIndex) => {
			const wos = byWeek.get(weekIndex)!;
			const target_volume_m = wos.reduce((s, w) => s + (w.target_distance_m ?? 0), 0);
			return {
				week_index: weekIndex,
				phase: phaseFor(weekIndex, totalWeeks) as PlanPhase,
				target_volume_m,
				notes: null,
				workouts: wos.map((w) => ({
					scheduled_date: w.scheduled_date,
					kind: w.kind,
					target_distance_m: w.target_distance_m,
					target_duration_seconds: null,
					target_pace_sec_per_km: w.target_pace_sec_per_km,
					target_pace_tolerance_sec: null,
					structure: null,
					notes: w.notes,
				})),
			};
		});

	const goalEvent: GoalEvent =
		goalEventToken && GOAL_EVENTS.includes(goalEventToken as GoalEvent)
			? (goalEventToken as GoalEvent)
			: 'custom';
	// For a known event use the canonical distance — the table's "Goal
	// distance" line is rounded to 2 dp of km (42.20 km), so trusting it
	// would round a marathon's 42195 m to 42200. For a custom event keep
	// the parsed distance, falling back to the longest workout.
	let resolvedDistance: number;
	if (goalEvent !== 'custom') {
		resolvedDistance = GOAL_DISTANCES_M[goalEvent];
	} else if (goalDistanceM != null && goalDistanceM > 0) {
		resolvedDistance = goalDistanceM;
	} else {
		resolvedDistance = Math.max(0, ...rows.map((r) => r.target_distance_m ?? 0));
	}
	if (!(resolvedDistance > 0)) {
		throw new PlanParseError('Could not determine a goal distance.');
	}

	const start = startDate && ISO_DATE.test(startDate) ? startDate : rows[0].scheduled_date;
	const endDate = rows[rows.length - 1].scheduled_date;

	return {
		name: name || 'Imported plan',
		goalEvent,
		goalDistanceM: resolvedDistance,
		goalTimeSec,
		startDate: start,
		generated: {
			weeks,
			paces: { easy: 0, marathon: 0, tempo: 0, interval: 0, repetition: 0 },
			vdot: null,
			endDate,
			goalDistanceM: resolvedDistance,
			pacesAreFallback: true,
		},
	};
}

/// Parse a JSON export (the `ExportPlan` shape) back into a plan ready
/// for `createTrainingPlan`. Round-trips with `planToJson`.
export function parsePlanJson(text: string): ParsedPlan {
	let obj: unknown;
	try {
		obj = JSON.parse(text);
	} catch {
		throw new PlanParseError('Not valid JSON.');
	}
	const p = obj as Partial<ExportPlan>;
	if (!p || !Array.isArray(p.workouts)) {
		throw new PlanParseError('JSON is missing a workouts array.');
	}
	// Re-route through the Markdown builder so JSON + Markdown share one
	// reconstruction path (phase recompute, volume summing, validation).
	return parsePlanMarkdown(
		planToMarkdown({
			name: p.name ?? 'Imported plan',
			goalEvent: p.goalEvent ?? 'custom',
			goalDistanceM: p.goalDistanceM ?? 0,
			goalTimeSec: p.goalTimeSec ?? null,
			startDate: p.startDate ?? '',
			workouts: p.workouts as ExportWorkout[],
		}),
	);
}
