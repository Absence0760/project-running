import type { ActivityType } from '$lib/types';
import type { MessageKey } from '$lib/i18n/messages';

/// The `runs.activity_type` value domain, in the order every picker shows it.
///
/// Authoritative source is the SQL CHECK constraint `runs_activity_type_check`
/// (migration `20261207_001`); the `ActivityType` union in `types.ts` mirrors
/// it per the narrow-union rule, and this array mirrors the union. All three
/// move together — `activity_type_vocabulary.test.ts` fails the build if the
/// CHECK, the array, or the catalogues drift apart.
export const ACTIVITY_TYPES = ['run', 'walk', 'hike', 'cycle', 'stroller'] as const;

/// Material Symbols ligature per value. Lives beside the label so a picker
/// cannot pair one surface's icon with another surface's word.
export const ACTIVITY_TYPE_ICONS: Record<ActivityType, string> = {
	run: 'directions_run',
	walk: 'directions_walk',
	hike: 'terrain',
	cycle: 'directions_bike',
	stroller: 'child_friendly',
};

/// The one catalogue key per value. Every surface that names an activity type
/// resolves through here, so two surfaces cannot disagree about what `hike`
/// is called.
export function activityTypeKey(value: ActivityType): MessageKey {
	return `activityType.${value}` as MessageKey;
}

export function isActivityType(value: string): value is ActivityType {
	return (ACTIVITY_TYPES as readonly string[]).includes(value);
}

/// Icon for a stored value, defaulting to `run` like the column does.
export function activityTypeIcon(value: string | null | undefined): string {
	const v = value ?? 'run';
	return isActivityType(v) ? ACTIVITY_TYPE_ICONS[v] : ACTIVITY_TYPE_ICONS.run;
}
