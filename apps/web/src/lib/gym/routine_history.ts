// "How has this routine actually gone?" — the read-back half of the guided
// session's execution trio (`routine_id` / `gym_step_results` / `gym_adherence`,
// metadata.md). Every guided session stamps the link, but nothing has ever read
// it per-routine, so a lifter could not see when they last ran a routine or
// whether they were finishing it.
//
// The tallies arrive already reduced, from the `gym_routine_history` RPC
// (migration 20270528_001): a count is an aggregate, and a windowed client read
// cannot serve one honestly — the previous 500-row window silently under-
// reported a decade of weekly sessions. What stays here is the display shaping
// the server has no business deciding: which verdict each row of the bounded
// recent page carries, its order, the floored days-since-last against the
// READER's clock, and the completed-of-graded ratio.
//
// Pure — no Svelte / Supabase dependencies, so it runs under `npx tsx --test`.
// TS↔Dart parity pair with `apps/mobile_android/lib/routine_history.dart` —
// keep the algorithm, edge cases, outputs, and test counts in lockstep.

import { hasSessionDraft } from './gym_session_draft';
import type { RoutineVerdict } from './gym_adherence';

/// A session that carries the routine link but no verdict is `ungraded`: the
/// runner left mid-session and chose "Save as is", which strips the draft
/// marker and keeps `routine_id` while deliberately claiming no adherence
/// (gym_session_draft.stripSessionDraft). It happened, so it counts as a
/// session, but it can be neither a completion nor a failure.
export type RoutineSessionVerdict = RoutineVerdict | 'ungraded';

export interface RoutineSessionRow {
	id: string;
	started_at: string;
	title?: string | null;
	metadata?: unknown;
}

/// One `gym_routine_history` row: complete tallies over every session the
/// routine has ever been run as, plus the explicitly bounded page of the most
/// recent ones the panel lists.
export interface RoutineHistoryAggregate {
	sessionCount: number;
	lastPerformedAt: string | null;
	gradedCount: number;
	completedCount: number;
	recentRows: readonly RoutineSessionRow[];
}

export interface RoutineSession {
	id: string;
	startedAt: string;
	startedAtMs: number;
	title: string | null;
	verdict: RoutineSessionVerdict;
}

export interface RoutineHistory {
	/// Only the page the aggregate carried — never the whole history. Named for
	/// what it is so no surface can present it as everything.
	recentSessions: RoutineSession[];
	sessionCount: number;
	lastPerformedAt: string | null;
	daysSinceLast: number | null;
	gradedCount: number;
	completedCount: number;
	completedRate: number | null;
}

const VERDICTS: readonly string[] = ['completed', 'partial', 'abandoned'];

const DAY_MS = 86_400_000;

function verdictOf(metadata: unknown): RoutineSessionVerdict {
	if (!metadata || typeof metadata !== 'object') return 'ungraded';
	const v = (metadata as Record<string, unknown>)['gym_adherence'];
	return typeof v === 'string' && VERDICTS.includes(v) ? (v as RoutineVerdict) : 'ungraded';
}

/// Shape one routine's server-side aggregate into what the history panel reads.
///
/// Rows still carrying a `gym_session_draft` snapshot are dropped from the
/// page: an in-flight session is not a session performed. The RPC applies the
/// same exclusion to the tallies, so filtering here keeps the listed rows from
/// ever contradicting the count they sit under.
export function routineHistoryFromAggregate(
	agg: RoutineHistoryAggregate,
	nowMs: number,
): RoutineHistory {
	const recentSessions: RoutineSession[] = [];
	for (const row of agg.recentRows) {
		if (!row || typeof row.id !== 'string' || row.id === '') continue;
		if (hasSessionDraft(row.metadata)) continue;
		const ms = Date.parse(row.started_at);
		if (!Number.isFinite(ms)) continue;
		recentSessions.push({
			id: row.id,
			startedAt: row.started_at,
			startedAtMs: ms,
			title: row.title ?? null,
			verdict: verdictOf(row.metadata),
		});
	}
	recentSessions.sort((a, b) => b.startedAtMs - a.startedAtMs);

	// Taken from the aggregate, not from the page: a bounded page can be empty
	// while the routine has been run hundreds of times.
	const lastMs = agg.lastPerformedAt == null ? NaN : Date.parse(agg.lastPerformedAt);
	const graded = Math.max(0, agg.gradedCount);
	const completed = Math.max(0, agg.completedCount);

	return {
		recentSessions,
		sessionCount: Math.max(0, agg.sessionCount),
		lastPerformedAt: agg.lastPerformedAt,
		// A row stamped ahead of the reader's clock reads as today, never as a
		// negative "in -2 days".
		daysSinceLast: Number.isFinite(lastMs) ? Math.max(0, Math.floor((nowMs - lastMs) / DAY_MS)) : null,
		gradedCount: graded,
		completedCount: completed,
		completedRate: graded === 0 ? null : completed / graded,
	};
}
