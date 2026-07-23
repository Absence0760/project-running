/// Build-time index of the Learn guides. Each guide is a `.md` file
/// under `./guides/` whose YAML frontmatter mdsvex exposes as the
/// module's `metadata` export and whose body compiles to a Svelte
/// component (the `default` export). `import.meta.glob(..., { eager:
/// true })` resolves every file at build time, so the hub + article +
/// category routes prerender to static HTML with zero runtime cost.
///
/// The pure index operations (list / resolve / group / localize) live in
/// `guides_index.ts` so they're unit-testable under `tsx` without Vite's
/// glob transform; this module only loads the glob and binds those
/// helpers to the built index. Filename convention: `<slug>.md` is the
/// English guide; a localized variant is `<slug>.<locale>.md` (e.g.
/// `road-running-101.de.md`). `getGuide(slug, locale)` resolves the
/// active locale's file and falls back to English when a localized file
/// is absent — wired now even though only English files are authored in
/// this phase.

import * as idx from './guides_index';
import type { GuideIndexEntry, GuideMeta, GuideModule } from './guides_index';
import { isKnownCategory, isKnownCtaFeature } from './categories';

export type {
	GuideFrontmatter,
	GuideComponent,
	GuideModule,
	GuideIndexEntry,
	GuideMeta,
} from './guides_index';

const DEFAULT_LOCALE = idx.DEFAULT_LOCALE;

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

export function listGuides(): GuideIndexEntry[] {
	return idx.listGuides(ALL_ENTRIES);
}

export function listGuideSlugs(): string[] {
	return idx.listGuideSlugs(ALL_ENTRIES);
}

export function getGuide(slug: string, locale: string = DEFAULT_LOCALE): GuideIndexEntry | null {
	return idx.getGuide(ALL_ENTRIES, slug, locale);
}

export function isEnglishFallback(slug: string, locale: string): boolean {
	return idx.isEnglishFallback(ALL_ENTRIES, slug, locale);
}

export function localizedGuideMeta(slug: string, locale: string = DEFAULT_LOCALE): GuideMeta | null {
	return idx.localizedGuideMeta(ALL_ENTRIES, slug, locale);
}

export function guidesByCategory(category: string): GuideIndexEntry[] {
	return idx.guidesByCategory(ALL_ENTRIES, category);
}

export function nonEmptyCategories() {
	return idx.nonEmptyCategories(ALL_ENTRIES);
}

export { isKnownCategory, isKnownCtaFeature };
