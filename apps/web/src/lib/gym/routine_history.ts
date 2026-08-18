// "How has this routine actually gone?" — the read-back half of the guided
// session's execution trio (`routine_id` / `gym_step_results` / `gym_adherence`,
// metadata.md). Every guided session stamps the link, but nothing has ever read
// it per-routine, so a lifter could not see when they last ran a routine or
// whether they were finishing it.
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

export interface RoutineSession {
	id: string;
	startedAt: string;
	startedAtMs: number;
	title: string | null;
	verdict: RoutineSessionVerdict;
}

export interface RoutineHistory {
	sessions: RoutineSession[];
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

/// Reduce the workout rows linked to one routine into its performance history.
///
/// Rows still carrying a `gym_session_draft` snapshot are dropped: an in-flight
/// session is not a session performed, and counting one would let a page
/// refresh inflate the routine's usage.
export function summariseRoutineHistory(
	rows: readonly RoutineSessionRow[],
	nowMs: number,
): RoutineHistory {
	const sessions: RoutineSession[] = [];
	for (const row of rows) {
		if (!row || typeof row.id !== 'string' || row.id === '') continue;
		if (hasSessionDraft(row.metadata)) continue;
		const ms = Date.parse(row.started_at);
		if (!Number.isFinite(ms)) continue;
		sessions.push({
			id: row.id,
			startedAt: row.started_at,
			startedAtMs: ms,
			title: row.title ?? null,
			verdict: verdictOf(row.metadata),
		});
	}
	sessions.sort((a, b) => b.startedAtMs - a.startedAtMs);

	const graded = sessions.filter((s) => s.verdict !== 'ungraded');
	const completedCount = sessions.filter((s) => s.verdict === 'completed').length;
	const last = sessions[0] ?? null;

	return {
		sessions,
		sessionCount: sessions.length,
		lastPerformedAt: last?.startedAt ?? null,
		// A row stamped ahead of the reader's clock reads as today, never as a
		// negative "in -2 days".
		daysSinceLast: last == null ? null : Math.max(0, Math.floor((nowMs - last.startedAtMs) / DAY_MS)),
		gradedCount: graded.length,
		completedCount,
		completedRate: graded.length === 0 ? null : completedCount / graded.length,
	};
}
