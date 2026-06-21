/**
 * expandSessionSteps — the session-plan analogue of the gym routine engine's
 * expand-once helper. Flattens a plan's blocks + items into the ordered list of
 * SessionSteps the editor preview, the read view, and (in P2) the follow-along
 * runner all consume.
 *
 * Pure + deterministic + clock-free so both platforms render an identical step
 * list and the future runner is unit-testable without a timer.
 *
 * Rules (session_planner.md § The expand-once helper):
 *  - order: blocks ascending by `position`, each block's items ascending by
 *    `position`; any blockless items (a flat plan) follow, ascending by
 *    `position`. Ties broken by input order (a stable sort).
 *  - a `per_side` item splits into two consecutive steps carrying the same
 *    movementName/kind/duration/reps/cue/tempo, distinguished by `side`
 *    ('left' then 'right'); the read view localizes the side word (the engine
 *    never bakes an English suffix into movementName — that would leak
 *    untranslated English into a non-English UI).
 *  - each step carries cumulative time = sum of every prior step's contribution
 *    plus its own; a `reps` step (or any step with no positive duration)
 *    contributes 0 to the time estimate (the runner waits on a Done tap).
 *
 * Dart twin: apps/mobile_android/lib/session_steps.dart — keep in lockstep
 * (same algorithm, edge cases, outputs, and test count).
 */

export type SessionItemKind = 'hold' | 'reps' | 'flow';

export interface SessionPlanItemInput {
	id: string;
	block_id: string | null;
	position: number;
	movement_name: string;
	kind: SessionItemKind;
	duration_s: number | null;
	reps: number | null;
	per_side: boolean;
	tempo: string | null;
	cue: string | null;
}

export interface SessionPlanBlockInput {
	id: string;
	position: number;
	name: string | null;
}

export interface SessionPlanInput {
	blocks: SessionPlanBlockInput[];
	items: SessionPlanItemInput[];
}

export interface SessionStep {
	itemId: string;
	movementName: string;
	kind: SessionItemKind;
	durationS: number | null;
	reps: number | null;
	tempo: string | null;
	cue: string | null;
	/** null for a non-per-side item, else 'left' | 'right'. */
	side: 'left' | 'right' | null;
	/** seconds elapsed at the end of this step (a no-duration step adds 0). */
	cumulativeS: number;
}

export interface ExpandedSession {
	steps: SessionStep[];
	totalS: number;
}

/** The positive-duration contribution of a step to the time estimate (else 0). */
function stepDurationS(durationS: number | null): number {
	// Number.isFinite + Math.floor guard against NaN/Infinity/fractional inputs
	// only because TS numbers are floats; the int-native Dart twin's `int?`
	// can't carry those, so the guards have no Dart counterpart by design — not
	// parity drift.
	if (durationS === null || !Number.isFinite(durationS) || durationS <= 0) return 0;
	return Math.floor(durationS);
}

/** Stable ascending sort by `position`, ties broken by original index. */
function byPosition<T extends { position: number }>(rows: T[]): T[] {
	return rows
		.map((row, index) => ({ row, index }))
		.sort((a, b) => a.row.position - b.row.position || a.index - b.index)
		.map((wrapped) => wrapped.row);
}

export function expandSessionSteps(plan: SessionPlanInput): ExpandedSession {
	const orderedItems: SessionPlanItemInput[] = [];

	for (const block of byPosition(plan.blocks)) {
		const blockItems = plan.items.filter((item) => item.block_id === block.id);
		orderedItems.push(...byPosition(blockItems));
	}
	const blockless = plan.items.filter((item) => item.block_id === null);
	orderedItems.push(...byPosition(blockless));

	const steps: SessionStep[] = [];
	let cumulative = 0;

	const pushStep = (item: SessionPlanItemInput, side: 'left' | 'right' | null) => {
		cumulative += stepDurationS(item.duration_s);
		steps.push({
			itemId: item.id,
			movementName: item.movement_name,
			kind: item.kind,
			durationS: item.duration_s,
			reps: item.reps,
			tempo: item.tempo,
			cue: item.cue,
			side,
			cumulativeS: cumulative
		});
	};

	for (const item of orderedItems) {
		if (item.per_side) {
			pushStep(item, 'left');
			pushStep(item, 'right');
		} else {
			pushStep(item, null);
		}
	}

	return { steps, totalS: cumulative };
}

export interface SessionStepResult {
	itemId: string;
	movementName: string;
	kind: SessionItemKind;
	side: 'left' | 'right' | null;
	targetDurationS: number | null;
	actualDurationS: number | null;
	status: 'completed' | 'skipped';
}

export interface SessionAdherence {
	completedSteps: number;
	totalSteps: number;
	adherencePct: number;
	verdict: 'completed' | 'partial' | 'abandoned';
}

export function computeSessionAdherence(
	steps: SessionStep[],
	results: SessionStepResult[]
): SessionAdherence {
	const totalSteps = steps.length;
	const stepIds = new Set(steps.map((s) => s.itemId));
	const completedSteps = Math.min(
		results.filter((r) => r.status === 'completed' && stepIds.has(r.itemId)).length,
		totalSteps
	);
	const adherencePct = totalSteps === 0 ? 0 : Math.min(1, completedSteps / totalSteps);

	let verdict: SessionAdherence['verdict'];
	if (completedSteps === 0) verdict = 'abandoned';
	else if (adherencePct >= 0.8) verdict = 'completed';
	else verdict = 'partial';

	return { completedSteps, totalSteps, adherencePct, verdict };
}
