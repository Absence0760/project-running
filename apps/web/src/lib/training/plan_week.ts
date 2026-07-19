/**
 * Which week of a training plan a given day falls in.
 *
 * The offset between the plan's start date and today is counted in whole UTC
 * epoch-days rather than by subtracting two local-midnight `Date` values: a
 * local-midnight span that crosses a DST transition is not an exact multiple
 * of 86.4M ms (it is ±1h), so raw local-ms division would `Math.floor` a day
 * short and, on a 7-day boundary, report the previous week. Mirrors the
 * `isoToEpochDay` approach in `cycle_plan.ts`.
 */

function isoToEpochDay(iso: string): number {
	const [y, m, d] = iso.split('-').map((n) => parseInt(n, 10));
	return Math.floor(Date.UTC(y, m - 1, d) / 86_400_000);
}

export function currentPlanWeekIndex(
	startDateIso: string,
	todayIso: string,
	weekCount: number
): number {
	const dayIndex = isoToEpochDay(todayIso) - isoToEpochDay(startDateIso);
	if (dayIndex < 0) return 0;
	return Math.min(weekCount - 1, Math.floor(dayIndex / 7));
}
