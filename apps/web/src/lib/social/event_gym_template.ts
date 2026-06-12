/**
 * The class -> gym seam: a typed contract over the loose `events.gym_template`
 * jsonb bag (migration 20261227_001 + the SELECT grant in 20261230_001).
 *
 * `gym_template` is meaningful only for `category === 'class'`. A host attaches
 * an optional discipline + default duration; an attendee one-tap-logs the class
 * as a gym workout, pre-filled from this template (they confirm in the composer
 * — inform-tier, nothing auto-writes).
 *
 * Dart twin: `apps/mobile_android/lib/event_gym_template.dart` — keep in
 * lockstep (same parse tolerance, same build rules, same draft shape).
 */

export interface EventGymTemplate {
	discipline: string | null;
	duration_min: number | null;
}

/** The minimal GymEditor seed the seam produces from a template. */
export interface GymWorkoutDraft {
	title: string | null;
	duration_s: number | null;
}

function asString(v: unknown): string | null {
	if (typeof v !== 'string') return null;
	const t = v.trim();
	return t === '' ? null : t;
}

function asPositiveInt(v: unknown): number | null {
	if (typeof v !== 'number' || !Number.isFinite(v)) return null;
	const n = Math.floor(v);
	return n > 0 ? n : null;
}

/**
 * Parse the raw jsonb into a typed template, tolerant of the loose bag.
 * Returns `null` when the value is absent, malformed, or carries neither a
 * discipline nor a duration (an effectively-empty template), so callers can
 * treat "no template" and "empty template" identically.
 */
export function parseGymTemplate(json: unknown): EventGymTemplate | null {
	if (json == null || typeof json !== 'object' || Array.isArray(json)) return null;
	const bag = json as Record<string, unknown>;
	const discipline = asString(bag.discipline);
	const duration_min = asPositiveInt(bag.duration_min);
	if (discipline === null && duration_min === null) return null;
	return { discipline, duration_min };
}

/**
 * Build the template to persist from the editor inputs. Returns `null` when
 * both are empty so a class without a template writes NULL (not `{}`), which
 * keeps the attendee affordance hidden for an un-templated class.
 */
export function gymTemplateFromInputs(
	discipline: string | null | undefined,
	durationMin: number | null | undefined
): EventGymTemplate | null {
	const d = asString(discipline ?? null);
	const m = asPositiveInt(durationMin ?? null);
	if (d === null && m === null) return null;
	return { discipline: d, duration_min: m };
}

/**
 * Produce the GymEditor prefill from a template. The title falls back to the
 * event title when the class carries no discipline; sets stay empty for the
 * user to fill in the composer.
 */
export function workoutDraftFromTemplate(
	template: EventGymTemplate | null,
	eventTitle: string | null | undefined
): GymWorkoutDraft {
	const title = template?.discipline ?? asString(eventTitle ?? null);
	const min = template?.duration_min ?? null;
	return {
		title,
		duration_s: min === null ? null : min * 60
	};
}
