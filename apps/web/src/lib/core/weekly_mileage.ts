/// Pure week-bucketing for the dashboard weekly-mileage chart, extracted
/// from `fetchWeeklyMileage` so the year-stable keying is unit-testable.
///
/// Runs are grouped into Monday-start weeks. The bucket key is the week
/// start's year-stable ISO date (`yyyy-mm-dd`): a day/month-only key (e.g.
/// "5 Jan") merged the same calendar week across different years, fusing
/// two New Year's weeks into a single bar. The human `week` label stays in
/// the prior `d MMM` form. Distance stays in metres; render-time formatting
/// honours the user's unit. Output is sorted chronologically and capped to
/// the most recent `maxWeeks`.

export interface WeekBar {
	week: string;
	distance_m: number;
}

export function bucketWeeklyMileage(
	runs: { started_at: string; distance_m: number }[],
	maxWeeks = 12,
): WeekBar[] {
	const weeks = new Map<string, { label: string; distance_m: number }>();
	for (const run of runs) {
		const d = new Date(run.started_at);
		const weekStart = new Date(d);
		weekStart.setDate(d.getDate() - ((d.getDay() + 6) % 7)); // Monday-start, matches goals.ts
		weekStart.setHours(0, 0, 0, 0);
		const key = `${weekStart.getFullYear()}-${String(weekStart.getMonth() + 1).padStart(2, '0')}-${String(weekStart.getDate()).padStart(2, '0')}`;
		const label = weekStart.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
		const cur = weeks.get(key);
		if (cur) cur.distance_m += run.distance_m;
		else weeks.set(key, { label, distance_m: run.distance_m });
	}

	return Array.from(weeks.entries())
		.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
		.slice(-maxWeeks)
		.map(([, w]) => ({ week: w.label, distance_m: Math.round(w.distance_m) }));
}
