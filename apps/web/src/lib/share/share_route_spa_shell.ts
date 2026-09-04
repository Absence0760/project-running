/// Inject per-route `<head>` meta tags into a SvelteKit SPA-shell HTML
/// template at request time. Pure — separated from the Lambda handler
/// so the substitution logic is unit-testable without an AWS event in
/// scope. Mirror of share_run_spa_shell.ts.
///
/// The strategy: SvelteKit's adapter-static builds an `index.html`
/// fallback served for any non-prerendered route. It carries a generic
/// `<head>` (default title + og:image pointing at the favicon). At
/// deploy time the share-route Lambda's bundler embeds that file as a
/// string; per request the Lambda calls `injectShareRouteMeta` to
/// splice in the route-specific tags.
///
/// Splice points beyond the run case: the route head also carries a
/// `<link rel="canonical">` and a JSON-LD `<script>`, so any stale
/// copies of those in the SPA shell are stripped before the per-route
/// ones are appended (a duplicate canonical / second WebPage node
/// would confuse crawlers).

import {
	renderShareRouteHeadTags,
	type ShareRouteHead,
} from './share_route_meta';

export function injectShareRouteMeta(
	spaShellHtml: string,
	head: ShareRouteHead,
): string {
	const newTags = renderShareRouteHeadTags(head);
	let out = spaShellHtml;
	// Strip the existing <title> so the new one (inside newTags) wins.
	out = out.replace(/<title(?=[\s/>])[^>]*>[\s\S]*?<\/title(?=[\s/>])[^>]*>/i, '');
	// Strip stale og:* / twitter:* / description meta — adapter-static
	// emits a default set that would render as duplicates of our
	// per-route tags and confuse some crawlers (Slackbot picks the
	// first; Twitterbot picks the last).
	out = out.replace(
		/<meta\s+(?:property|name)="(?:og:[^"]+|twitter:[^"]+|description)"[^>]*>/gi,
		'',
	);
	// Strip any existing canonical link + JSON-LD block so the per-route
	// ones don't sit alongside a stale default. Two parser rules the naive
	// spelling gets wrong. The end tag is `</script` followed by whitespace,
	// `/` or `>`, then junk up to the first `>` (js/bad-tag-filter): against
	// `</script >` a `<\/script>` close does not stop there, so the lazy body
	// runs on to the NEXT `</script>` in the document -- the SPA bundle's --
	// and takes `</head>`, the mount div and the bundle tag with it, at which
	// point the splice below finds no head and returns the wreckage unmeta'd.
	// And the open tag is any `<script>` carrying the ld+json type, not one
	// exact attribute spelling, so a nonce or a reordered attribute cannot
	// leave a stale block standing. The strip repeats until the string stops
	// changing so a crafted/overlapping `<script ...><script>...</script>`
	// can't leave a residual `<script` behind
	// (js/incomplete-multi-character-sanitization).
	out = out.replace(/<link\s+rel="canonical"[^>]*>/gi, '');
	let prev: string;
	do {
		prev = out;
		out = out.replace(
			/<script(?=[\s/>])[^>]*\stype="application\/ld\+json"[^>]*>[\s\S]*?<\/script(?=[\s/>])[^>]*>/gi,
			'',
		);
	} while (out !== prev);
	// Splice the new tags in just before </head>.
	const insertedAt = out.search(/<\/head(?=[\s/>])[^>]*>/i);
	if (insertedAt === -1) {
		// SPA shell is malformed — return as-is rather than synthesise a
		// head wrapper that might not match the SvelteKit shape. Caller's
		// caching + monitoring catches this case.
		return out;
	}
	return out.slice(0, insertedAt) + newTags + '\n' + out.slice(insertedAt);
}
