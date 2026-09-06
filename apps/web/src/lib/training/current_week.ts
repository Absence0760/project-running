/**
 * Current-calendar-week derivation for the dashboard "This Week" strip.
 *
 * Unlike the plan-detail CurrentWeekStrip (which anchors its 7-day window
 * to the plan's `start_date + week_index*7` so its count matches the week
 * card), this strip is the runner's REAL calendar week — the seven days of
 * the week that contains `now`, starting on the user's `week_start` pref —
 * with each day's logged-activity distance + count folded in.
 *
 * Pure: no Supabase, no DOM, no rune state — so it unit-tests under
 * `tsx --test`, and it is the web half of a registered parity pair with the
 * Dart twin `apps/mobile_android/lib/current_week.dart`. Keep the algorithm,
 * edge cases, outputs, and test counts in lockstep. (The WIDGET that renders
 * it is `apps/mobile_android/lib/widgets/current_week_strip.dart`, which is
 * not a twin of anything.)
 */

export type WeekStart = 'monday' | 'sunday';

/// The minimum an activity needs to expose for the strip: when it happened
/// and how far it went. `started_at` is an ISO timestamp; `distance_m` is
/// metres. The dashboard feeds its already-fetched `Run[]` straight in.
export interface WeekActivity {
	started_at: string;
	distance_m: number;
}

/// One day of the strip. `iso` is the local `yyyy-mm-dd` date; `dow` is the
/// JS day-of-week (0 = Sunday) so the caller can index its localized
/// weekday labels; `distanceM` / `count` aggregate the day's activities;
/// `isToday` / `isFuture` drive the cell's highlight + dimming.
export interface WeekDay {
	iso: string;
	dow: number;
	distanceM: number;
	count: number;
	isToday: boolean;
	isFuture: boolean;
}

/// The whole strip: its seven ordered days plus the week's running totals,
/// so a header can show "12.4 km · 3 activities" without re-summing.
export interface CurrentWeek {
	days: WeekDay[];
	totalDistanceM: number;
	totalCount: number;
}

/// Local `yyyy-mm-dd` for a date — NOT `toISOString()`, which would shift
/// across the UTC boundary and bucket a late-evening run into the wrong
/// day. Mirrors the Dart twin's `_localIso`.
function localIso(d: Date): string {
	const y = d.getFullYear();
	const mo = String(d.getMonth() + 1).padStart(2, '0');
	const da = String(d.getDate()).padStart(2, '0');
	return `${y}-${mo}-${da}`;
}

/// Midnight (local) at the start of the calendar week containing `now`,
/// honouring `weekStart`. Same offset math the dashboard's inline
/// `weekStart` derived used before this was lifted to a shared helper.
function weekStartMidnight(now: Date, weekStart: WeekStart): Date {
	const ws = new Date(now);
	const offset = weekStart === 'sunday' ? now.getDay() : (now.getDay() + 6) % 7;
	ws.setDate(now.getDate() - offset);
	ws.setHours(0, 0, 0, 0);
	return ws;
}

/// Build the current calendar week from `activities`, bucketing each one
/// onto its LOCAL day. Activities outside the week (or with a non-positive
/// distance) are ignored. `now` defaults to the real clock; pass an
/// explicit date in tests + on the server for determinism.
export function currentWeek(
	activities: WeekActivity[],
	weekStart: WeekStart = 'monday',
	now: Date = new Date(),
): CurrentWeek {
	const start = weekStartMidnight(now, weekStart);
	const todayIso = localIso(now);

	const byDay = new Map<string, { distanceM: number; count: number }>();
	for (const a of activities) {
		const dist = a.distance_m;
		if (!(dist > 0)) continue;
		const t = new Date(a.started_at);
		if (Number.isNaN(t.getTime())) continue;
		const iso = localIso(t);
		const cur = byDay.get(iso);
		if (cur) {
			cur.distanceM += dist;
			cur.count += 1;
		} else {
			byDay.set(iso, { distanceM: dist, count: 1 });
		}
	}

	const days: WeekDay[] = [];
	let totalDistanceM = 0;
	let totalCount = 0;
	for (let i = 0; i < 7; i++) {
		const d = new Date(start);
		d.setDate(start.getDate() + i);
		const iso = localIso(d);
		const agg = byDay.get(iso) ?? { distanceM: 0, count: 0 };
		days.push({
			iso,
			dow: d.getDay(),
			distanceM: agg.distanceM,
			count: agg.count,
			isToday: iso === todayIso,
			isFuture: iso > todayIso,
		});
		totalDistanceM += agg.distanceM;
		totalCount += agg.count;
	}

	return { days, totalDistanceM, totalCount };
}
