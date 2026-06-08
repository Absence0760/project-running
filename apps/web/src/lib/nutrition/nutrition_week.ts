/**
 * Weekly intake summary — is the last 7 days of logging trending over or
 * under the daily calorie goal?
 *
 * Averages over *logged* days only, so an unlogged day never reads as a fake
 * deficit (this is also the reference-average the trend bars draw).
 *
 * The non-obvious choice: the delta compares the logged-day average to
 * *today's* full calorie goal. Past days had their own (unstored) goals, so
 * this is an honest "typical day vs goal" read, not a per-day reconciliation.
 *
 * Web-only for now; mobile mirror tracked in followups.md.
 */

export interface WeeklyIntakeSummary {
	loggedDays: number;
	/// Mean intake across logged days (0 when nothing is logged).
	avgCalories: number;
	/// Signed avg − target over logged days: positive = over goal (surplus),
	/// negative = under (deficit). Null when there's no target or no logged day.
	deltaPerDay: number | null;
}

export function weeklyIntakeSummary(
	dailyCalories: number[],
	targetCalories: number | null | undefined,
): WeeklyIntakeSummary {
	const logged = dailyCalories.filter((c) => c > 0);
	const loggedDays = logged.length;
	const avgCalories =
		loggedDays > 0 ? Math.round(logged.reduce((s, c) => s + c, 0) / loggedDays) : 0;
	const deltaPerDay =
		targetCalories != null && targetCalories > 0 && loggedDays > 0
			? avgCalories - targetCalories
			: null;
	return { loggedDays, avgCalories, deltaPerDay };
}
