/// Generic SPA-shell `<head>` injector for the entity-SSR Lambda. Pure —
/// separated from the Lambda handler so the substitution logic is
/// unit-testable without an AWS event in scope. Generalises
/// share_route_spa_shell.ts: rather than take a typed head object, it
/// takes an ALREADY-RENDERED head-tags string (produced by any of the
/// render*HeadTags builders — event / profile / club / race), so one
/// injector serves every entity type the shared Lambda dispatches.
///
/// The strategy is the same as the per-type shells: SvelteKit's
/// adapter-static builds an `index.html` fallback with a generic `<head>`;
/// at deploy time the Lambda's bundler embeds that file as a string, and
/// per request the Lambda strips the shell's stale title / og / twitter /
/// description / canonical / JSON-LD and splices in the per-entity tags
/// before `</head>` so no duplicate signals reach a crawler.

import { escapeHtml } from '../util/html_escape';

export function injectEntityHead(spaShellHtml: string, headTags: string): string {
	let out = spaShellHtml;
	// Strip the existing <title> so the new one (inside headTags) wins.
	out = out.replace(/<title>[\s\S]*?<\/title>/i, '');
	// Strip stale og:* / twitter:* / description meta — adapter-static
	// emits a default set that would render as duplicates and confuse
	// some crawlers (Slackbot picks the first; Twitterbot the last).
	out = out.replace(
		/<meta\s+(?:property|name)="(?:og:[^"]+|twitter:[^"]+|description)"[^>]*>/gi,
		'',
	);
	// Strip any existing canonical link + JSON-LD block so the per-entity
	// ones don't sit alongside a stale default. The JSON-LD strip repeats
	// until the string stops changing so a crafted/overlapping
	// `<script ...><script>…</script>` can't leave a residual `<script`
	// behind (js/incomplete-multi-character-sanitization).
	out = out.replace(/<link\s+rel="canonical"[^>]*>/gi, '');
	let prev: string;
	do {
		prev = out;
		out = out.replace(
			/<script\s+type="application\/ld\+json">[\s\S]*?<\/script>/gi,
			'',
		);
	} while (out !== prev);
	const insertedAt = out.search(/<\/head>/i);
	if (insertedAt === -1) {
		// SPA shell is malformed — return as-is rather than synthesise a
		// head wrapper that might not match the SvelteKit shape. Caller's
		// caching + monitoring catches this case.
		return out;
	}
	return out.slice(0, insertedAt) + headTags + '\n' + out.slice(insertedAt);
}

/// The 404 body: the app's own shell, told not to be indexed.
///
/// Every share Lambda used to answer its own hand-written sentence here --
/// `<p>This link isn't available.</p>`, unstyled, unlocalized, no navigation,
/// five slightly different spellings of it. A reader never saw one because the
/// distribution replaces every 4xx body with `/index.html` (decisions § 1022),
/// which is the SPA shell -- so the designed `.notfound-card` rendered and the
/// `noindex` these handlers send was thrown away with the body.
///
/// Returning the shell HERE makes the handler and the edge agree: the reader
/// gets the same designed, localized card either way, and the `noindex`
/// survives, at which point the distribution's 404 mapping is redundant rather
/// than load-bearing (filed for the infra tree).
///
/// `title` stays per-surface and stays English: it is the tab title before
/// hydration, exactly like every other prerendered page's, and the app sets its
/// own once running.
export function notFoundShell(spaShellHtml: string, title: string): string {
	const head = `<title>${escapeHtml(title)}</title>\n<meta name="robots" content="noindex">`;
	// A shell the bundler never substituted, or one with no `</head>` to splice
	// into, must still answer a noindex 404: these handlers exist to tell a
	// crawler the entity is GONE, and a throw here would reach the outer
	// envelope and answer 503 -- a retry signal for something that will never
	// come back. `injectEntityHead` returns a spliceable-less shell unchanged,
	// which would carry no noindex at all, so both cases resolve here.
	if (typeof spaShellHtml !== 'string' || !/<\/head>/i.test(spaShellHtml)) {
		return `<!doctype html><html lang="en"><head><meta charset="utf-8">${head}</head><body></body></html>`;
	}
	return injectEntityHead(spaShellHtml, head);
}
