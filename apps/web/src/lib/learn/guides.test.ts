import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { isKnownCategory, isKnownCtaFeature } from './categories';
import { SUPPORTED_LOCALES, DEFAULT_LOCALE } from '../i18n/locale';

// guides.ts loads its index via `import.meta.glob`, a Vite-only
// transform that doesn't resolve under raw tsx. So this guard reads the
// `.md` files straight off disk and parses their YAML frontmatter — the
// same files the glob picks up at build time — and validates every
// guide's required frontmatter, slug uniqueness, category membership,
// and CTA target against the pure categories catalogue. A malformed new
// guide fails CI here rather than shipping a broken page.

const here = dirname(fileURLToPath(import.meta.url));
const guidesDir = join(here, 'guides');

type Frontmatter = Record<string, unknown>;

function parseFrontmatter(src: string): Frontmatter {
	const match = src.match(/^---\n([\s\S]*?)\n---/);
	assert.ok(match, 'guide is missing a YAML frontmatter block');
	const fm: Frontmatter = {};
	const lines = match[1].split('\n');
	let nested: Record<string, unknown> | null = null;
	let nestedKey = '';
	for (const raw of lines) {
		if (raw.trim() === '') continue;
		const indented = /^\s+\S/.test(raw);
		const [k, ...rest] = raw.trim().split(':');
		const value = rest.join(':').trim();
		if (indented && nested) {
			nested[k] = stripQuotes(value);
			continue;
		}
		if (value === '') {
			nested = {};
			nestedKey = k;
			fm[nestedKey] = nested;
		} else {
			nested = null;
			fm[k] = stripQuotes(value);
		}
	}
	return fm;
}

function stripQuotes(s: string): string {
	return s.replace(/^['"]|['"]$/g, '');
}

function parseStem(file: string): { slug: string; locale: string } {
	const stem = file.replace(/\.md$/, '');
	const dot = stem.indexOf('.');
	if (dot === -1) return { slug: stem, locale: 'en' };
	return { slug: stem.slice(0, dot), locale: stem.slice(dot + 1) };
}

const files = readdirSync(guidesDir).filter((f) => f.endsWith('.md'));

test('there is at least one guide', () => {
	assert.ok(files.length > 0, 'no .md guides found');
});

test('every guide has the required frontmatter and a valid category + CTA', () => {
	for (const file of files) {
		const src = readFileSync(join(guidesDir, file), 'utf8');
		const fm = parseFrontmatter(src);
		const { slug } = parseStem(file);

		for (const key of ['title', 'description', 'category', 'slug', 'order', 'updated']) {
			const v = fm[key];
			assert.ok(
				typeof v === 'string' && v.trim().length > 0,
				`${file}: frontmatter '${key}' is missing or empty`,
			);
		}

		assert.equal(fm.slug, slug, `${file}: frontmatter slug must equal the filename stem`);
		assert.ok(
			isKnownCategory(fm.category as string),
			`${file}: unknown category '${fm.category as string}'`,
		);
		assert.match(
			fm.updated as string,
			/^\d{4}-\d{2}-\d{2}$/,
			`${file}: 'updated' must be an ISO date (YYYY-MM-DD)`,
		);
		assert.ok(
			Number.isFinite(Number(fm.order)),
			`${file}: 'order' must be a number`,
		);

		const cta = fm.cta as Record<string, unknown> | undefined;
		if (cta && cta.feature) {
			assert.ok(
				isKnownCtaFeature(cta.feature as string),
				`${file}: unknown cta.feature '${cta.feature as string}'`,
			);
		}
	}
});

test('English guide slugs are unique', () => {
	const seen = new Set<string>();
	for (const file of files) {
		const { slug, locale } = parseStem(file);
		if (locale !== 'en') continue;
		assert.ok(!seen.has(slug), `duplicate English guide slug '${slug}'`);
		seen.add(slug);
	}
});

// A localized file is `<slug>.<locale>.md`. The resolver in guides.ts keys
// off the suffix, so the suffix MUST be a real supported locale and there
// MUST be an English source to fall back to — otherwise getGuide can never
// pick the file and isEnglishFallback lies about it. These guards keep the
// authored translations honest as the set grows.

const englishSlugs = new Set(
	files.map(parseStem).filter((p) => p.locale === DEFAULT_LOCALE).map((p) => p.slug),
);

test('every localized guide suffix is a supported, non-default locale', () => {
	for (const file of files) {
		const { locale } = parseStem(file);
		if (locale === DEFAULT_LOCALE) continue;
		assert.ok(
			(SUPPORTED_LOCALES as readonly string[]).includes(locale),
			`${file}: '${locale}' is not a supported locale (${SUPPORTED_LOCALES.join(', ')})`,
		);
	}
});

test('every localized guide has an English source to fall back to', () => {
	for (const file of files) {
		const { slug, locale } = parseStem(file);
		if (locale === DEFAULT_LOCALE) continue;
		assert.ok(
			englishSlugs.has(slug),
			`${file}: localized variant has no English '${slug}.md' source`,
		);
	}
});

test('a localized guide is unique per (slug, locale)', () => {
	const seen = new Set<string>();
	for (const file of files) {
		const { slug, locale } = parseStem(file);
		if (locale === DEFAULT_LOCALE) continue;
		const key = `${slug}.${locale}`;
		assert.ok(!seen.has(key), `duplicate localized guide '${key}'`);
		seen.add(key);
	}
});

test('localized frontmatter agrees with its English sibling on slug, category, order, and CTA', () => {
	const enFrontmatter = new Map<string, Frontmatter>();
	for (const file of files) {
		const { slug, locale } = parseStem(file);
		if (locale !== DEFAULT_LOCALE) continue;
		enFrontmatter.set(slug, parseFrontmatter(readFileSync(join(guidesDir, file), 'utf8')));
	}

	for (const file of files) {
		const { slug, locale } = parseStem(file);
		if (locale === DEFAULT_LOCALE) continue;
		const en = enFrontmatter.get(slug);
		assert.ok(en, `${file}: no English source frontmatter`);
		const fm = parseFrontmatter(readFileSync(join(guidesDir, file), 'utf8'));

		assert.equal(fm.slug, slug, `${file}: frontmatter slug must equal the filename stem-slug`);
		// The hub/category card route + section are driven off the English
		// index; a localized file that disagrees on category or order would
		// produce a card that links to a body filed under a different
		// section. Title + description deliberately DIFFER (they localize).
		assert.equal(
			fm.category,
			en!.category,
			`${file}: category '${String(fm.category)}' must match the English '${String(en!.category)}'`,
		);
		assert.equal(
			String(fm.order),
			String(en!.order),
			`${file}: order must match the English source`,
		);
		const ctaFeature = (fm.cta as Record<string, unknown> | undefined)?.feature;
		const enCtaFeature = (en!.cta as Record<string, unknown> | undefined)?.feature;
		assert.equal(
			ctaFeature ?? null,
			enCtaFeature ?? null,
			`${file}: cta.feature must match the English source`,
		);
	}
});
