// The one home for the workout-kind marker hue, read by PlanCalendar.svelte and
// CurrentWeekStrip.svelte. Mirrors apps/mobile_android/lib/workout_kind_color.dart;
// the VALUES live once per brightness as --kind-1..--kind-6 in app.css and their
// mobile twins in ui_kit's ChartPalette.kinds, asserted in lockstep by
// contrast_guard.test.ts.
//
// The colour is a MARK — the 3 px cell edge — and never type. Nine kinds share
// six marks, so the hue alone cannot name a kind even to a reader with full
// colour vision; the localized kind word beside the mark is what identifies it.

/// Ladder index into the `--kind-*` scale for a `plan_workouts.kind` value. The
/// six groups are the order the scale is defined in, so a greyscale reader gets
/// a stable ordering. An unknown kind falls to `rest`, the quietest mark, rather
/// than to a text token that would reintroduce a tinted label.
export function workoutKindMarkIndex(kind: string): number {
	switch (kind) {
		case 'easy':
		case 'recovery':
			return 1;
		case 'long':
		case 'race':
			return 2;
		case 'tempo':
			return 3;
		case 'marathon_pace':
			return 4;
		case 'interval':
		case 'walk_run':
			return 5;
		default:
			return 6;
	}
}

export function workoutKindMarkVar(kind: string): string {
	return `var(--kind-${workoutKindMarkIndex(kind)})`;
}
