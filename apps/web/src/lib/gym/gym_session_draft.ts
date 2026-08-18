// The in-flight snapshot behind the gym-session resume path: the runner's
// ordered per-step outcomes, stamped onto the draft `gym_workouts` row's
// metadata under `gym_session_draft` (registered in docs/backend/metadata.md).
//
// The wire shape is a cross-platform contract, not a web convention — mobile
// writes and replays the same key (decisions.md § 483), so a draft left on one
// platform has to resume on the other. Two consequences bind this module:
// `results` is DENSE and in step order, because the mobile side replays it
// positionally through its runner API; and the current step is DERIVED from
// the replay rather than stored, so a routine edited between save and resume
// degrades to "replay what still fits" instead of landing on a phantom step.
//
// Pure — no Svelte, no Supabase — so it runs under `npx tsx --test`.

import type { EnteredSet, StepOutcome } from './gym_session_types';

export const GYM_SESSION_DRAFT_KEY = 'gym_session_draft';

export interface GymSessionDraftResult {
	step_index: number;
	status: 'completed' | 'skipped';
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
	duration_s: number | null;
	distance_m: number | null;
}

export interface GymSessionDraft {
	saved_at: string;
	results: GymSessionDraftResult[];
}

export interface RestoredSession {
	outcomes: (StepOutcome | undefined)[];
	currentIndex: number;
}

function num(v: unknown): number | null {
	return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/// The outcomes of every step the runner has already left behind. Steps at or
/// after `currentIndex` are excluded: the step being worked on has no outcome
/// yet, and storing one would make the resume land a step ahead of the runner.
export function draftResults(
	outcomes: readonly (StepOutcome | undefined)[],
	currentIndex: number,
): GymSessionDraftResult[] {
	const out: GymSessionDraftResult[] = [];
	const end = Math.max(0, Math.min(currentIndex, outcomes.length));
	for (let i = 0; i < end; i++) {
		const o = outcomes[i];
		if (!o || o.kind === 'skipped') {
			out.push({
				step_index: i,
				status: 'skipped',
				reps: null,
				weight_kg: null,
				rpe: null,
				duration_s: null,
				distance_m: null,
			});
			continue;
		}
		const e = o.entered;
		out.push({
			step_index: i,
			status: 'completed',
			reps: e.reps,
			weight_kg: e.weightKg,
			rpe: e.rpe,
			duration_s: e.durationS,
			distance_m: e.distanceM,
		});
	}
	return out;
}

/// The whole metadata bag a durable save writes: the routine link plus the
/// snapshot. Finish replaces this with the execution trio, which is what
/// clears the draft marker.
export function draftMetadata(
	routineId: string,
	outcomes: readonly (StepOutcome | undefined)[],
	currentIndex: number,
	savedAtIso: string,
): Record<string, unknown> {
	return {
		routine_id: routineId,
		[GYM_SESSION_DRAFT_KEY]: {
			saved_at: savedAtIso,
			results: draftResults(outcomes, currentIndex),
		} satisfies GymSessionDraft,
	};
}

// `typeof x === 'object'` is true for null AND for arrays, so it is not the
// "is this a JSON object" test it reads as. The marker's shape is a
// cross-platform contract: Dart asks `is Map` and the `gym_routine_history`
// RPC asks `jsonb_typeof(...) = 'object'`, so an array under the key has to
// answer "not a draft" here too, or a row three rails call performed reads as
// in-flight on one of them.
function isJsonObject(v: unknown): v is Record<string, unknown> {
	return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function draftOf(metadata: unknown): { results: unknown } | null {
	if (!isJsonObject(metadata)) return null;
	const snap = metadata[GYM_SESSION_DRAFT_KEY];
	if (!isJsonObject(snap)) return null;
	return snap as { results: unknown };
}

export function hasSessionDraft(metadata: unknown): boolean {
	return draftOf(metadata) !== null;
}

/// The routine a draft belongs to, or null when the bag carries no usable link
/// — a draft whose routine is unknown can't be replayed against anything.
export function draftRoutineId(metadata: unknown): string | null {
	if (!hasSessionDraft(metadata)) return null;
	const id = (metadata as Record<string, unknown>)['routine_id'];
	return typeof id === 'string' && id !== '' ? id : null;
}

/// Sets the runner actually logged, for the resume card's summary. Skipped
/// steps are outcomes but not sets.
export function draftLoggedCount(metadata: unknown): number {
	const snap = draftOf(metadata);
	if (!snap || !Array.isArray(snap.results)) return 0;
	return snap.results.filter(
		(r) => r && typeof r === 'object' && (r as { status?: unknown }).status === 'completed',
	).length;
}

/// Rebuild the runner's position from a snapshot. Null when the bag carries no
/// draft; an unreadable `results` degrades to a fresh start on the same row
/// rather than forking a second draft.
export function restoreSessionDraft(metadata: unknown, stepCount: number): RestoredSession | null {
	const snap = draftOf(metadata);
	if (!snap) return null;
	const outcomes: (StepOutcome | undefined)[] = new Array(stepCount).fill(undefined);
	if (!Array.isArray(snap.results)) return { outcomes, currentIndex: 0 };

	let i = 0;
	for (const raw of snap.results) {
		if (i >= stepCount) break;
		if (!raw || typeof raw !== 'object') break;
		const r = raw as Record<string, unknown>;
		if (r.status === 'completed') {
			const entered: EnteredSet = {
				reps: num(r.reps),
				weightKg: num(r.weight_kg),
				rpe: num(r.rpe),
				durationS: num(r.duration_s),
				distanceM: num(r.distance_m),
			};
			outcomes[i] = { kind: 'logged', entered };
		} else {
			outcomes[i] = { kind: 'skipped' };
		}
		i++;
	}
	return { outcomes, currentIndex: i };
}

/// Re-anchor elapsed to `now − saved duration_s` so resuming continues from the
/// last durable save instead of billing the runner for the time the tab was
/// closed. Mirrors `resumeSession` on the run side.
export function resumedStartedAt(durationS: number | null | undefined, nowMs: number): string {
	const s = num(durationS);
	const back = s != null && s > 0 ? s * 1000 : 0;
	return new Date(nowMs - back).toISOString();
}

/// "Save as is": keep the logged sets as a plain workout by dropping only the
/// draft marker. `routine_id` stays (the link is real); no adherence verdict is
/// claimed, because the session never ran to completion.
export function stripSessionDraft(metadata: unknown): Record<string, unknown> {
	if (!isJsonObject(metadata)) return {};
	const out = { ...metadata };
	delete out[GYM_SESSION_DRAFT_KEY];
	return out;
}
