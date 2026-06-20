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
