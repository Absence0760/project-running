/// Inject per-run `<head>` meta tags into a SvelteKit SPA-shell HTML
/// template at request time. Pure — separated from the Lambda
/// handler so the substitution logic is unit-testable without an
/// AWS event in scope.
///
/// The strategy: SvelteKit's adapter-static builds an `index.html`
/// fallback that's served for any non-prerendered route. It contains
/// a generic `<head>` (the default site title + og:image pointing
/// at the favicon). At deploy time, the share-run Lambda's bundler
/// reads that file and embeds it as a string. Per request the
/// Lambda calls `injectShareRunMeta` to splice in the run-specific
/// tags.
///
/// Two splice points:
///   1. Replace the existing `<title>` so the browser tab + crawler
///      title both reflect the run.
///   2. Append the new OG / Twitter tags before `</head>` so they
///      sit alongside (and override) any defaults the SPA shell
///      already carries.
///
/// Persona-hunt finding Casual #4.

import { renderShareRunHeadTags, type ShareRunMeta } from './share_run_meta';

export function injectShareRunMeta(
	spaShellHtml: string,
	meta: ShareRunMeta,
): string {
	const newTags = renderShareRunHeadTags(meta);
	// Strip the existing <title> so the new one (inside newTags) wins.
	// Also strip stale og:* / twitter:* meta tags from the SPA shell
	// — adapter-static emits a default set that would render as
	// duplicates of our per-run tags and confuse some crawlers
	// (Slackbot picks the first; Twitterbot picks the last).
	let out = spaShellHtml;
	out = out.replace(/<title>[\s\S]*?<\/title>/i, '');
	out = out.replace(
		/<meta\s+(?:property|name)="(?:og:[^"]+|twitter:[^"]+|description)"[^>]*>/gi,
		'',
	);
	// Splice the new tags in just before </head>. Case-insensitive
	// match against the closing tag.
	const insertedAt = out.search(/<\/head>/i);
	if (insertedAt === -1) {
		// SPA shell is malformed — return as-is rather than synthesise
		// a head wrapper that might not match the SvelteKit shape.
		// Caller's caching + monitoring catches this case.
		return out;
	}
	return out.slice(0, insertedAt) + newTags + '\n' + out.slice(insertedAt);
}
