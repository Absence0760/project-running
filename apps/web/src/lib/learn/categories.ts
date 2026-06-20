/// The fixed catalogue of Learn-guide categories + the in-app CTA
/// target map. Pure (no runes) so guides.ts can validate every guide's
/// `category` + `cta.feature` against these at unit-test time.
///
/// Category ids are short, stable kebab-case strings used in the URL
/// (`/learn/category/<id>`). `labelKey` resolves through the i18n `m()`
/// helper; `order` controls section ordering on the hub.

export type LearnCategory = {
	id: string;
	labelKey: string;
	order: number;
};

export const CATEGORIES: LearnCategory[] = [
	{ id: 'getting-started', labelKey: 'learn.catGettingStarted', order: 1 },
	{ id: 'gear', labelKey: 'learn.catGear', order: 2 },
	{ id: 'training', labelKey: 'learn.catTraining', order: 3 },
	{ id: 'nutrition', labelKey: 'learn.catNutrition', order: 4 },
	{ id: 'racing', labelKey: 'learn.catRacing', order: 5 },
	{ id: 'trail', labelKey: 'learn.catTrail', order: 6 },
];

const CATEGORY_IDS = new Set(CATEGORIES.map((c) => c.id));

export function isKnownCategory(id: string): boolean {
	return CATEGORY_IDS.has(id);
}

export function getCategory(id: string): LearnCategory | undefined {
	return CATEGORIES.find((c) => c.id === id);
}

/// The end-of-article CTA targets. Each guide's frontmatter `cta.feature`
/// names one of these; the article template renders a card linking to
/// `route` with the i18n'd `labelKey`. All targets are auth-gated app
/// routes — an anon reader who clicks is sent through the layout auth
/// guard to `/login?return_to=...`, which is the intended acquisition
/// funnel.
///
/// `racing` deliberately points at `/social?tab=clubs`: there is no
/// public race-calendar feature shipped yet (clubs have events, but no
/// aggregated race-finder). When a race calendar ships, repoint this
/// entry — see docs/features/learn.md.
export type CtaTarget = {
	feature: string;
	route: string;
	labelKey: string;
};

export const CTA_TARGETS: CtaTarget[] = [
	{ feature: 'training-plans', route: '/plans/new', labelKey: 'learn.ctaTrainingPlans' },
	{ feature: 'route-builder', route: '/routes/new', labelKey: 'learn.ctaRouteBuilder' },
	{ feature: 'gear', route: '/settings', labelKey: 'learn.ctaGear' },
	{ feature: 'nutrition', route: '/nutrition', labelKey: 'learn.ctaNutrition' },
	{ feature: 'ai-coach', route: '/coach', labelKey: 'learn.ctaAiCoach' },
	{ feature: 'clubs', route: '/social?tab=clubs', labelKey: 'learn.ctaClubs' },
	{ feature: 'racing', route: '/social?tab=clubs', labelKey: 'learn.ctaRacing' },
	{ feature: 'explore', route: '/routes?tab=explore', labelKey: 'learn.ctaExplore' },
];

const CTA_BY_FEATURE = new Map(CTA_TARGETS.map((t) => [t.feature, t]));

export function getCtaTarget(feature: string): CtaTarget | undefined {
	return CTA_BY_FEATURE.get(feature);
}

export function isKnownCtaFeature(feature: string): boolean {
	return CTA_BY_FEATURE.has(feature);
}
