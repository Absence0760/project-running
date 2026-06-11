import type { EventCategory } from '$lib/types';

/**
 * Event categories, in the order shown in the create-event picker.
 *
 * Dart twin: `apps/mobile_android/lib/event_category.dart` — keep in lockstep
 * (same set, same order, same athletic split).
 */
export const EVENT_CATEGORIES: readonly EventCategory[] = ['run', 'cycle', 'class', 'social'];

/**
 * Distance-based athletic events (run / cycle) carry a course — route,
 * distance, target pace — can be run as a live race, and carry a results
 * leaderboard + finisher certificates. Instructor-led classes and social
 * meetups do none of that; they are attendance-only.
 *
 * This is the single source of truth the web + mobile event surfaces gate
 * every athletic affordance on. The database enforces the same split at the
 * data layer via the race_sessions / event_results triggers (migration
 * 20261227_001), so a non-athletic event is un-race-able / un-result-able
 * even via a direct API call — this predicate only governs what the UI shows.
 */
export function isAthleticCategory(category: EventCategory): boolean {
	return category === 'run' || category === 'cycle';
}
