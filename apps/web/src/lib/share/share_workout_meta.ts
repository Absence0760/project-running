/// Per-workout `<head>` meta-tag + JSON-LD builders for the public
/// share-workout page. Pure string helpers — used by the SvelteKit
/// +page.svelte (dev-server SSR) and the production entity-SSR Lambda.
///
/// Privacy boundary: every field read here comes from what
/// `share_workout_lookup` selects out of the redacted `public_gym_workouts`
/// / `public_gym_sets` views. The owner's free-text `notes`
/// (`gym_workouts.notes`, up to 1000 chars) and per-set `rpe` are absent
/// from those views by design (migration 20270313_001 / 20270327_001) and
/// must never reach a meta tag — an og:description is handed to every
/// unfurler that touches the link, including ones the owner never shared it
/// with. The lookup shape is the allow-list; do not widen it to feed a
/// richer description.
///
/// Units are canonical kg and the date is UTC, deliberately ignoring the
/// viewer's `preferred_unit` and locale: an unfurl must not change with who
/// triggered the scrape. `formatWeight` from `units.svelte` reads per-viewer
/// reactive state and is therefore wrong here — see share_meta.ts's header
/// for the full argument.

import { formatDateStable, normaliseSiteUrl } from './share_meta';
import { distinctExerciseCount as countDistinctExercises } from '../gym/gym_prs';
import { escapeHtml } from '../util/html_escape';
import type { SharedWorkout, SharedWorkoutSet } from './share_workout_lookup';

const SITE_NAME = 'Threkir';

function escapeJsonLd(json: string): string {
	return json
		.replace(/</g, '\\u003c')
		.replace(/>/g, '\\u003e')
		.replace(/&/g, '\\u0026');
}

function clean(raw: string | null | undefined, max: number): string {
	const collapsed = (raw ?? '').replace(/\s+/g, ' ').trim();
	if (!collapsed) return '';
	return collapsed.length > max ? `${collapsed.slice(0, max - 1).trimEnd()}…` : collapsed;
}

/// Total kilograms lifted, rounded — canonical kg, never the viewer's unit.
export function formatKgStable(kg: number | null | undefined): string {
	if (kg == null || !Number.isFinite(kg) || kg <= 0) return '';
	return `${Math.round(kg)} kg`;
}

/// Distinct exercises in a logged workout, counted on the CANONICAL grouping
/// key. Shared with the share page so its summary tile and the og:description
/// can't disagree about the number.
///
/// The key has one derivation — `normaliseExerciseName` (§ 1175) — and this
/// used to re-derive it as `trim().toLowerCase()` under a comment claiming
/// case- and whitespace-insensitive matching. It was neither: measured, a
/// workout logging "Bench  Press" beside "Bench Press", "Bench\u00a0Press"
/// beside "bench press", or "\u0130ncline Press" beside "incline press"
/// counted TWO where `gym_workout_summaries` and every keyed surface count
/// one, and the number went out in an og:description to every unfurler that
/// touched the link (§ 1274).
export function distinctExerciseCount(sets: readonly SharedWorkoutSet[]): number {
	return countDistinctExercises(sets.map((s) => s.exercise_name));
}

export function buildWorkoutShareTitle(
	workout: SharedWorkout | null | undefined,
	displayName?: string | null,
): string {
	if (!workout) return `Workout — ${SITE_NAME}`;
	const custom = clean(workout.title, 80);
	if (custom) return `${custom} — ${SITE_NAME}`;
	const by = clean(displayName, 60);
	return by ? `Workout by ${by} — ${SITE_NAME}` : `Workout — ${SITE_NAME}`;
}

export function buildWorkoutShareDescription(
	workout: SharedWorkout | null | undefined,
	displayName?: string | null,
): string {
	if (!workout) return `View a public gym workout on ${SITE_NAME}.`;
	const bits: string[] = [];
	const exercises = distinctExerciseCount(workout.sets);
	if (exercises > 0) bits.push(`${exercises} ${exercises === 1 ? 'exercise' : 'exercises'}`);
	const sets = workout.set_count ?? workout.sets.length;
	if (sets > 0) bits.push(`${sets} ${sets === 1 ? 'set' : 'sets'}`);
	const volume = formatKgStable(workout.volume_kg);
	if (volume) bits.push(`${volume} lifted`);
	const by = clean(displayName, 60);
	if (by) bits.push(`by ${by}`);
	const date = formatDateStable(workout.started_at);
	if (date) bits.push(`on ${date}`);
	const lead = bits.length ? `${bits.join(' · ')}. ` : '';
	return `${lead}Log your lifts on ${SITE_NAME}.`.trim();
}

/// Absolute canonical URL for a public workout share page. The in-app
/// /gym/[id] surface points its canonical here — and builds its copyable
/// share link from the same helper — so search engines consolidate onto the
/// single public page and the two URLs can never drift apart.
export function buildWorkoutShareCanonical(
	base: string | null | undefined,
	id: string,
): string {
	return `${normaliseSiteUrl(base)}/share/workout/${id}`;
}

function workoutShareName(
	workout: SharedWorkout | null | undefined,
	displayName?: string | null,
): string {
	const full = buildWorkoutShareTitle(workout, displayName);
	const suffix = ` — ${SITE_NAME}`;
	return full.endsWith(suffix) ? full.slice(0, -suffix.length) : full;
}

/// schema.org JSON-LD for a public workout share page: a `WebPage` + a
/// `BreadcrumbList` (Home → workout), mirroring `buildRunJsonLd`.
///
/// `ExercisePlan` looks like the tailored type but is refused deliberately:
/// its supertype chain runs through `MedicalEntity`, which would publish a
/// person's training as medical structured data, and it describes a *plan*
/// rather than a performed session. `WebPage` + breadcrumb is the honest,
/// broadly-supported choice — the same reasoning that keeps a recorded run
/// on `WebPage`. No `primaryImageOfPage`: there is no per-workout OG PNG,
/// and pointing it at the brand card would misdescribe the page.
///
/// Title + display name are user-controlled, so the output goes through
/// `escapeJsonLd` before it reaches the DOM.
export function buildWorkoutJsonLd(
	workout: SharedWorkout | null | undefined,
	opts: { id: string; base: string | null | undefined; displayName?: string | null },
): string {
	const base = normaliseSiteUrl(opts.base);
	const canonical = buildWorkoutShareCanonical(base, opts.id);
	const name = workoutShareName(workout, opts.displayName);
	const graph = {
		'@context': 'https://schema.org',
		'@type': 'WebPage',
		name,
		description: buildWorkoutShareDescription(workout, opts.displayName),
		url: canonical,
		breadcrumb: {
			'@type': 'BreadcrumbList',
			itemListElement: [
				{ '@type': 'ListItem', position: 1, name: SITE_NAME, item: `${base}/` },
				{ '@type': 'ListItem', position: 2, name },
			],
		},
	};
	return escapeJsonLd(JSON.stringify(graph));
}

export interface ShareWorkoutMetaInput {
	id: string;
	workout: SharedWorkout | null;
	displayName: string | null;
	siteUrl: string;
}

export interface ShareWorkoutHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildShareWorkoutHead(input: ShareWorkoutMetaInput): ShareWorkoutHead {
	const { id, workout, displayName, siteUrl } = input;
	const base = normaliseSiteUrl(siteUrl);
	return {
		title: buildWorkoutShareTitle(workout, displayName),
		description: buildWorkoutShareDescription(workout, displayName),
		canonical: buildWorkoutShareCanonical(siteUrl, id),
		ogImageUrl: `${base}/og-default.png`,
		jsonLd: buildWorkoutJsonLd(workout, { id, base: siteUrl, displayName }),
	};
}

export function renderShareWorkoutHeadTags(head: ShareWorkoutHead): string {
	const e = escapeHtml;
	return [
		`<title>${e(head.title)}</title>`,
		`<meta name="description" content="${e(head.description)}">`,
		`<link rel="canonical" href="${e(head.canonical)}">`,
		`<meta property="og:title" content="${e(head.title)}">`,
		`<meta property="og:description" content="${e(head.description)}">`,
		`<meta property="og:type" content="article">`,
		`<meta property="og:url" content="${e(head.canonical)}">`,
		`<meta property="og:image" content="${e(head.ogImageUrl)}">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:site_name" content="${SITE_NAME}">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		`<meta name="twitter:title" content="${e(head.title)}">`,
		`<meta name="twitter:description" content="${e(head.description)}">`,
		`<meta name="twitter:image" content="${e(head.ogImageUrl)}">`,
		`<script type="application/ld+json">${head.jsonLd}</script>`,
	].join('\n\t');
}
