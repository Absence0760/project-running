import { getAdminClient } from './local-supabase';

/** The seeded Sydney Half plan (runner@test.com / USER_A owns it). */
export const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

/**
 * The fixed date the seed authors the plan against (`seed.sql` ~line 848).
 * The seed slides the whole plan onto a now()-relative window via a uniform
 * day offset; this is the origin those literal seed dates are measured from.
 */
const SEED_PLAN_START = '2026-03-29';

function utcMs(iso: string): number {
	const [y, m, d] = iso.split('-').map(Number);
	return Date.UTC(y, m - 1, d);
}

function daysBetween(aIso: string, bIso: string): number {
	return Math.round((utcMs(aIso) - utcMs(bIso)) / 86_400_000);
}

function addDaysIso(iso: string, days: number): string {
	const [y, m, d] = iso.split('-').map(Number);
	return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/**
 * Resolve a date expressed in the plan's fixed "seed coordinates" (e.g.
 * `'2026-04-07'`, the literal date written in seed.sql) to the live
 * scheduled_date after the seed's now()-relative shift. Reads the plan's
 * current `start_date` and re-applies the same offset the seed used, so the
 * many `findWorkoutByDate('2026-04-..')` call sites and calendar month
 * assertions keep working without hard-coding any wall-clock date.
 */
export async function seedDateToLive(seedDate: string): Promise<string> {
	const offset = await seedShiftOffsetDays();
	return addDaysIso(seedDate, offset);
}

/** The uniform day offset the seed applied to slide the plan onto now(). */
export async function seedShiftOffsetDays(): Promise<number> {
	const admin = getAdminClient();
	const { data } = await admin
		.from('training_plans')
		.select('start_date')
		.eq('id', SYDNEY_HALF_PLAN_ID)
		.maybeSingle();
	const liveStart = (data as { start_date: string } | null)?.start_date;
	if (!liveStart) throw new Error('seed plan has no start_date');
	return daysBetween(liveStart, SEED_PLAN_START);
}

/** "MMMM YYYY" label (matching the calendar head) for a seed-coordinate date. */
export async function liveMonthLabel(seedDate: string): Promise<string> {
	const liveIso = await seedDateToLive(seedDate);
	const [y, m] = liveIso.split('-').map(Number);
	return new Date(Date.UTC(y, m - 1, 1)).toLocaleString('en-US', {
		month: 'long',
		year: 'numeric',
		timeZone: 'UTC'
	});
}

/**
 * Make the plan's TODAY workout a non-rest, matchable workout IN PLACE.
 *
 * The seed plan's dates are now()-relative, so on days it lands a rest day on
 * today, MOVING or INSERTING another workout onto today trips the
 * `plan_workouts_one_per_day` unique(week_id, scheduled_date) constraint. That
 * same constraint guarantees exactly one workout per day, so repurpose THAT row
 * — no date move, no second insert, no collision. (Several plan specs used to
 * move/insert a workout onto today and flaked only on days the seed placed a
 * rest day there — run 27565316836.)
 *
 * `fields` overrides the columns to set (default a 5000 m Easy). Returns the
 * workout id and an `undo` that restores the original values of those columns +
 * clears any completion link the test added.
 */
export async function repurposeTodayWorkout(
	fields: Record<string, unknown> = { kind: 'easy', target_distance_m: 5000 }
): Promise<{ workoutId: string; undo: () => Promise<void> }> {
	const admin = getAdminClient();
	const { data: weeks } = await admin
		.from('plan_weeks')
		.select('id')
		.eq('plan_id', SYDNEY_HALF_PLAN_ID);
	const weekIds = (weeks ?? []).map((w) => (w as { id: string }).id);
	const today = new Date().toISOString().slice(0, 10);
	// Read the columns we're about to overwrite so undo can put them back.
	const cols = ['id', ...Object.keys(fields)].join(', ');
	const { data: rows } = await admin
		.from('plan_workouts')
		.select(cols)
		.in('week_id', weekIds)
		.eq('scheduled_date', today)
		.limit(1);
	const original = rows?.[0] as Record<string, unknown> | undefined;
	if (!original) {
		// The seed plan's dates are fixed, so once real time marches past its
		// end_date no row covers today. There's then no one-per-day collision to
		// dodge — insert a workout for today and remove it on undo.
		if (weekIds.length === 0) throw new Error('seed plan has no weeks to insert into');
		const { data: ins, error: insErr } = await admin
			.from('plan_workouts')
			.insert({ week_id: weekIds[0], scheduled_date: today, ...fields })
			.select('id')
			.single();
		if (insErr || !ins) throw new Error(`could not insert today workout: ${insErr?.message}`);
		const insertedId = (ins as { id: string }).id;
		return {
			workoutId: insertedId,
			undo: async () => {
				await admin.from('plan_workouts').delete().eq('id', insertedId);
			}
		};
	}
	const workoutId = original.id as string;
	const { error } = await admin.from('plan_workouts').update(fields).eq('id', workoutId);
	if (error) throw error;
	return {
		workoutId,
		undo: async () => {
			const restore: Record<string, unknown> = {
				completed_run_id: null,
				manually_completed: false,
				completed_at: null
			};
			for (const k of Object.keys(fields)) restore[k] = original[k] ?? null;
			await admin.from('plan_workouts').update(restore).eq('id', workoutId);
		}
	};
}
