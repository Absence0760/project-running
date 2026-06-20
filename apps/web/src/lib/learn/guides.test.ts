import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { isKnownCategory, isKnownCtaFeature } from './categories';

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
