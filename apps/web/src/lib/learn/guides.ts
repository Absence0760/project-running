/// Build-time index of the Learn guides. Each guide is a `.md` file
/// under `./guides/` whose YAML frontmatter mdsvex exposes as the
/// module's `metadata` export and whose body compiles to a Svelte
/// component (the `default` export). `import.meta.glob(..., { eager:
/// true })` resolves every file at build time, so the hub + article +
/// category routes prerender to static HTML with zero runtime cost.
///
/// Pure (no runes) so the frontmatter + slug + category + CTA guards in
/// guides.test.ts run under `npx tsx --test`.
///
/// Filename convention: `<slug>.md` is the English guide; a future
/// localized variant is `<slug>.<locale>.md` (e.g. `road-running-101.de.md`).
/// `getGuide(slug, locale)` resolves the active locale's file and falls
/// back to English when a localized file is absent — the fallback is
/// wired now even though only English files are authored in this phase.

import type { Component } from 'svelte';
import { CATEGORIES, isKnownCategory, isKnownCtaFeature } from './categories';

export type GuideFrontmatter = {
	title: string;
	description: string;
	category: string;
	slug: string;
	order: number;
	updated: string;
	heroImage?: string;
	cta?: { feature: string };
};

export type GuideComponent = Component;

export type GuideModule = {
	metadata: GuideFrontmatter;
	default: GuideComponent;
};

export type GuideIndexEntry = {
	slug: string;
	locale: string;
	title: string;
	description: string;
	category: string;
	order: number;
	updated: string;
	heroImage?: string;
	cta?: { feature: string };
	component: GuideComponent;
};

const DEFAULT_LOCALE = 'en';

const modules = import.meta.glob<GuideModule>('./guides/*.md', { eager: true });

/// Parse a glob path like `./guides/road-running-101.de.md` into
/// `{ slug: 'road-running-101', locale: 'de' }`. A file with no locale
/// segment (`road-running-101.md`) is the English source.
function parseFilename(path: string): { slug: string; locale: string } {
	const stem = path.replace(/^.*\//, '').replace(/\.md$/, '');
	const dot = stem.indexOf('.');
	if (dot === -1) return { slug: stem, locale: DEFAULT_LOCALE };
	return { slug: stem.slice(0, dot), locale: stem.slice(dot + 1) };
}

function buildIndex(): GuideIndexEntry[] {
	const out: GuideIndexEntry[] = [];
	for (const [path, mod] of Object.entries(modules)) {
		const { slug, locale } = parseFilename(path);
		const fm = mod.metadata;
		out.push({
			slug,
			locale,
			title: fm.title,
			description: fm.description,
			category: fm.category,
			order: fm.order,
			updated: fm.updated,
			heroImage: fm.heroImage,
			cta: fm.cta,
			component: mod.default,
		});
	}
	return out;
}

const ALL_ENTRIES = buildIndex();

function byOrderThenTitle(a: GuideIndexEntry, b: GuideIndexEntry): number {
	if (a.order !== b.order) return a.order - b.order;
	return a.title.localeCompare(b.title);
}

/// Every English guide, ordered by `order` then title. The hub + sitemap
/// drive off the English set (one entry per slug); localized variants are
/// resolved per-request by getGuide.
export function listGuides(): GuideIndexEntry[] {
	return ALL_ENTRIES.filter((e) => e.locale === DEFAULT_LOCALE).sort(byOrderThenTitle);
}

export function listGuideSlugs(): string[] {
	return listGuides().map((e) => e.slug);
}

/// Resolve a guide by slug for the active locale, falling back to English
/// when no localized file exists. Returns `null` for an unknown slug.
export function getGuide(slug: string, locale: string = DEFAULT_LOCALE): GuideIndexEntry | null {
	const localized = ALL_ENTRIES.find((e) => e.slug === slug && e.locale === locale);
	if (localized) return localized;
	return ALL_ENTRIES.find((e) => e.slug === slug && e.locale === DEFAULT_LOCALE) ?? null;
}

/// True when the active-locale guide is being served as the English
/// fallback (no localized file for this slug). Drives the "this guide is
/// in English" notice on the article page.
export function isEnglishFallback(slug: string, locale: string): boolean {
	if (locale === DEFAULT_LOCALE) return false;
	return !ALL_ENTRIES.some((e) => e.slug === slug && e.locale === locale);
}

export type GuideMeta = {
	slug: string;
	title: string;
	description: string;
	category: string;
};

/// The localized title + description for a guide card. The hub + category
/// listings build off the English index (one card per slug), so a
/// non-English visitor would otherwise read an English title above a body
/// that localizes on the article page a click away. This re-resolves the
/// card's title + description from the active locale's frontmatter, falling
/// back to the English entry's field when the localized file is absent — so
/// the listing stays consistent with the article. Returns `null` for an
/// unknown slug.
export function localizedGuideMeta(slug: string, locale: string = DEFAULT_LOCALE): GuideMeta | null {
	const en = ALL_ENTRIES.find((e) => e.slug === slug && e.locale === DEFAULT_LOCALE);
	if (!en) return null;
	const localized =
		locale === DEFAULT_LOCALE
			? undefined
			: ALL_ENTRIES.find((e) => e.slug === slug && e.locale === locale);
	return {
		slug,
		title: localized?.title ?? en.title,
		description: localized?.description ?? en.description,
		category: en.category,
	};
}

export function guidesByCategory(category: string): GuideIndexEntry[] {
	return listGuides().filter((e) => e.category === category);
}

/// Categories that actually have at least one guide, in catalogue order.
/// The hub renders a section per non-empty category.
export function nonEmptyCategories() {
	return CATEGORIES.filter((c) => guidesByCategory(c.id).length > 0).sort(
		(a, b) => a.order - b.order,
	);
}

export { isKnownCategory, isKnownCtaFeature };
