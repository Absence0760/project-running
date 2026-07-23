/// Pure, env-free index operations over the Learn guides.
///
/// Split out from `guides.ts` (which binds to Vite's build-time
/// `import.meta.glob`, a transform that doesn't resolve under raw
/// `tsx`) so these list / resolve / group helpers are unit-testable
/// against a synthetic entry set. `guides.ts` re-exports thin
/// wrappers that bind the glob-built index. Mirrors the
/// `geocoding.ts` / `geocoding_math.ts` split.

import type { Component } from 'svelte';
import { CATEGORIES } from './categories';

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

export type GuideMeta = {
	slug: string;
	title: string;
	description: string;
	category: string;
};

export const DEFAULT_LOCALE = 'en';

function byOrderThenTitle(a: GuideIndexEntry, b: GuideIndexEntry): number {
	if (a.order !== b.order) return a.order - b.order;
	return a.title.localeCompare(b.title);
}

/// Every English guide, ordered by `order` then title. The hub + sitemap
/// drive off the English set (one entry per slug); localized variants are
/// resolved per-request by getGuide.
export function listGuides(entries: GuideIndexEntry[]): GuideIndexEntry[] {
	return entries.filter((e) => e.locale === DEFAULT_LOCALE).sort(byOrderThenTitle);
}

export function listGuideSlugs(entries: GuideIndexEntry[]): string[] {
	return listGuides(entries).map((e) => e.slug);
}

/// Resolve a guide by slug for the active locale, falling back to English
/// when no localized file exists. Returns `null` for an unknown slug.
export function getGuide(
	entries: GuideIndexEntry[],
	slug: string,
	locale: string = DEFAULT_LOCALE,
): GuideIndexEntry | null {
	const localized = entries.find((e) => e.slug === slug && e.locale === locale);
	if (localized) return localized;
	return entries.find((e) => e.slug === slug && e.locale === DEFAULT_LOCALE) ?? null;
}

/// True when the active-locale guide is being served as the English
/// fallback (no localized file for this slug). Drives the "this guide is
/// in English" notice on the article page.
export function isEnglishFallback(
	entries: GuideIndexEntry[],
	slug: string,
	locale: string,
): boolean {
	if (locale === DEFAULT_LOCALE) return false;
	return !entries.some((e) => e.slug === slug && e.locale === locale);
}

/// The localized title + description for a guide card. The hub + category
/// listings build off the English index (one card per slug), so a
/// non-English visitor would otherwise read an English title above a body
/// that localizes on the article page a click away. This re-resolves the
/// card's title + description from the active locale's frontmatter, falling
/// back to the English entry's field when the localized file is absent — so
/// the listing stays consistent with the article. Returns `null` for an
/// unknown slug.
export function localizedGuideMeta(
	entries: GuideIndexEntry[],
	slug: string,
	locale: string = DEFAULT_LOCALE,
): GuideMeta | null {
	const en = entries.find((e) => e.slug === slug && e.locale === DEFAULT_LOCALE);
	if (!en) return null;
	const localized =
		locale === DEFAULT_LOCALE
			? undefined
			: entries.find((e) => e.slug === slug && e.locale === locale);
	return {
		slug,
		title: localized?.title ?? en.title,
		description: localized?.description ?? en.description,
		category: en.category,
	};
}

export function guidesByCategory(entries: GuideIndexEntry[], category: string): GuideIndexEntry[] {
	return listGuides(entries).filter((e) => e.category === category);
}

/// Categories that actually have at least one guide, in catalogue order.
/// The hub renders a section per non-empty category.
export function nonEmptyCategories(entries: GuideIndexEntry[]) {
	return CATEGORIES.filter((c) => guidesByCategory(entries, c.id).length > 0).sort(
		(a, b) => a.order - b.order,
	);
}
