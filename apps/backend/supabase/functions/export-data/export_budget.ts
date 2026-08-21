/// The wall-clock budget the Art 20 export runs against.
///
/// Streaming the archive into Storage removed the memory ceiling that
/// forced the 5000-run and 50,000-row-per-section caps, but it cannot
/// remove the platform's request timeout. The Edge Function is killed at
/// `EXPORT_FUNCTION_TIMEOUT_MS`, and a killed request has no chance to
/// declare a length, sign a URL, or tell the caller what it managed —
/// the subject just sees a 500 and learns nothing.
///
/// So the surviving bound is the timeout itself, made explicit: the
/// builders stop opening new work once the budget is spent, mark what
/// they skipped, and finish the archive with a manifest that names the
/// shortfall. That is a real platform limit honestly reported, not a
/// row count picked to keep an allocation alive.

/// The platform's per-request wall clock for an Edge Function.
export const EXPORT_FUNCTION_TIMEOUT_MS = 150_000;

/// What the builders may spend. The remainder covers finalising the
/// upload (the last 6 MiB chunk), signing the URL and answering — all
/// of which happen after the last section is written and none of which
/// may be cut off, or the archive is lost rather than short.
export const EXPORT_WALL_CLOCK_BUDGET_MS = 120_000;

export interface ExportBudget {
	/// True once no new page or object should be started.
	expired(): boolean;
	remainingMs(): number;
	/// Names the sections that stopped short because the budget ran out,
	/// in the order they gave up. Feeds `manifest.json`'s `incomplete`.
	deadlineSkipped(): string[];
	noteSkipped(section: string): void;
}

export function createExportBudget(
	budgetMs: number = EXPORT_WALL_CLOCK_BUDGET_MS,
	now: () => number = Date.now,
): ExportBudget {
	const deadline = now() + budgetMs;
	const skipped: string[] = [];
	return {
		expired: () => now() >= deadline,
		remainingMs: () => Math.max(0, deadline - now()),
		deadlineSkipped: () => [...skipped],
		noteSkipped(section: string) {
			if (!skipped.includes(section)) skipped.push(section);
		},
	};
}
