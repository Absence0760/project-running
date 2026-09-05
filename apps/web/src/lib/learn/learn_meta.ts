/// Pure SEO builders for the Learn pages — sibling of share_meta.ts.
/// Splits the title / description / canonical / JSON-LD wire shape out
/// of the +page.svelte files so unit tests can pin them without booting
/// SvelteKit. Mirrors share_meta.ts's idioms (trailing-slash
/// normalisation + the JSON-LD escape) rather than abstracting them — a
/// three-line escape is not worth a shared module (conventions discourage
/// premature abstraction).

const SITE_NAME = 'Threkir';

/// Strip trailing slashes so `${base}/learn/...` joins single-slashed.
/// Tolerates null/undefined (returns ''), so a caller that hasn't
/// resolved PUBLIC_SITE_URL still emits a root-relative path.
export function normaliseSiteUrl(base: string | null | undefined): string {
	return (base ?? '').replace(/\/+$/, '');
}

/// Absolute canonical URL for any Learn path. `path` is a root-relative
/// path beginning with `/learn` (`/learn`, `/learn/<slug>`,
/// `/learn/category/<id>`).
export function buildLearnCanonical(base: string | null | undefined, path: string): string {
	const p = path.startsWith('/') ? path : `/${path}`;
	return `${normaliseSiteUrl(base)}${p}`;
}

export function buildGuideTitle(title: string | null | undefined): string {
	const t = (title ?? '').trim();
	return t ? `${t} — ${SITE_NAME}` : `Learn — ${SITE_NAME}`;
}

export function buildGuideDescription(description: string | null | undefined): string {
	const d = (description ?? '').trim();
	return d || `Beginner running guides on ${SITE_NAME}.`;
}

/// Escape the three characters that let a string break out of a
/// `<script type="application/ld+json">` block when injected verbatim
/// into HTML. `<` is the only strictly necessary one (`</script>`); the
/// other two keep the payload valid JSON either way (belt-and-braces).
function escapeJsonLd(json: string): string {
	return json
		.replace(/</g, '\\u003c')
		.replace(/>/g, '\\u003e')
		.replace(/&/g, '\\u0026');
}

export type GuideJsonLdInput = {
	title: string;
	description: string;
	slug: string;
	updated: string;
	categoryId: string;
	categoryLabel: string;
	base: string | null | undefined;
};

/// schema.org JSON-LD for a single guide: an `Article` node (headline,
/// description, published/modified dates, Organization author +
/// publisher, mainEntityOfPage canonical) plus a `BreadcrumbList`
/// (Home → Learn → category → article) for breadcrumb rich results.
/// Returns a string ready to drop inside a `<script
/// type="application/ld+json">`. Guide content is repo-authored, not
/// user input, but the output is still run through `escapeJsonLd` for
/// consistency + defence-in-depth.
export function buildGuideJsonLd(input: GuideJsonLdInput): string {
	const base = normaliseSiteUrl(input.base);
	const canonical = `${base}/learn/${input.slug}`;
	const graph = {
		'@context': 'https://schema.org',
		'@type': 'Article',
		headline: input.title,
		description: input.description,
		datePublished: input.updated,
		dateModified: input.updated,
		author: { '@type': 'Organization', name: SITE_NAME },
		publisher: { '@type': 'Organization', name: SITE_NAME },
		mainEntityOfPage: canonical,
		url: canonical,
		breadcrumb: {
			'@type': 'BreadcrumbList',
			itemListElement: [
				{ '@type': 'ListItem', position: 1, name: SITE_NAME, item: `${base}/` },
				{ '@type': 'ListItem', position: 2, name: 'Learn', item: `${base}/learn` },
				{
					'@type': 'ListItem',
					position: 3,
					name: input.categoryLabel,
					item: `${base}/learn/category/${input.categoryId}`,
				},
				{ '@type': 'ListItem', position: 4, name: input.title },
			],
		},
	};
	return escapeJsonLd(JSON.stringify(graph));
}

export type LearnCollectionEntry = { slug: string; title: string };

export type LearnCollectionJsonLdInput = {
	/// The page's rendered title and description — the same strings the
	/// `<title>` and `<meta name="description">` carry, so the structured
	/// data cannot describe a different page from the one served.
	title: string;
	description: string;
	/// The category this page indexes, or null for the `/learn` hub. Decides
	/// both the canonical path and how many breadcrumb rungs there are.
	category: { id: string; label: string } | null;
	/// The guides the page lists, in the order it lists them.
	guides: readonly LearnCollectionEntry[];
	base: string | null | undefined;
};

/// schema.org JSON-LD for the two Learn pages that index other pages: the
/// `/learn` hub and each `/learn/category/<id>`. A `CollectionPage` node —
/// NOT an `Article`, which is what a guide is; a hub that claimed to be an
/// article would be structured data describing a page that does not exist —
/// carrying a `BreadcrumbList` of the same rungs `buildGuideJsonLd` builds
/// (minus the article's own) and an `ItemList` of the guides listed.
///
/// The `ItemList` is omitted entirely when the page lists nothing, rather
/// than emitted empty: an empty collection is a claim, and the wrong one.
/// Returns a string ready to drop inside a `<script type="application/ld+json">`.
export function buildLearnCollectionJsonLd(input: LearnCollectionJsonLdInput): string {
	const base = normaliseSiteUrl(input.base);
	const path = input.category ? `/learn/category/${input.category.id}` : '/learn';
	const canonical = `${base}${path}`;

	// The last rung is the page being viewed, so it carries no `item` — the
	// shape Google documents and `buildGuideJsonLd` already uses.
	const crumbs: Record<string, unknown>[] = [
		{ '@type': 'ListItem', position: 1, name: SITE_NAME, item: `${base}/` },
	];
	if (input.category) {
		crumbs.push({ '@type': 'ListItem', position: 2, name: 'Learn', item: `${base}/learn` });
		crumbs.push({ '@type': 'ListItem', position: 3, name: input.category.label });
	} else {
		crumbs.push({ '@type': 'ListItem', position: 2, name: 'Learn' });
	}

	const node: Record<string, unknown> = {
		'@context': 'https://schema.org',
		'@type': 'CollectionPage',
		name: input.title,
		description: input.description,
		url: canonical,
		publisher: { '@type': 'Organization', name: SITE_NAME },
		breadcrumb: { '@type': 'BreadcrumbList', itemListElement: crumbs },
	};

	if (input.guides.length > 0) {
		node.mainEntity = {
			'@type': 'ItemList',
			numberOfItems: input.guides.length,
			itemListElement: input.guides.map((g, i) => ({
				'@type': 'ListItem',
				position: i + 1,
				name: g.title,
				url: `${base}/learn/${g.slug}`,
			})),
		};
	}

	return escapeJsonLd(JSON.stringify(node));
}
