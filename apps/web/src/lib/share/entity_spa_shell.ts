/// Generic SPA-shell `<head>` injector for the entity-SSR Lambda. Pure --
/// separated from the Lambda handler so the substitution logic is
/// unit-testable without an AWS event in scope. Generalises
/// share_route_spa_shell.ts: rather than take a typed head object, it
/// takes an ALREADY-RENDERED head-tags string (produced by any of the
/// render*HeadTags builders -- event / profile / club / race), so one
/// injector serves every entity type the shared Lambda dispatches.
///
/// The strategy is the same as the per-type shells: at deploy time the
/// Lambda's bundler embeds `apps/web/build/200.html` as a string, and per
/// request the Lambda strips the shell's stale signals and splices the
/// per-entity tags in before `</head>`. The strip/splice steps themselves live
/// once, in head_splice.ts.
///
/// All four signals are named here because an entity head supplies all four,
/// and because `notFoundShell` runs through this same function: a page that
/// says the entity is GONE must carry nothing about it, whatever the shell
/// arrived with. What the shell actually carries today is measured, not
/// assumed -- see spa_shell_head_signals.test.ts.

import { escapeHtml } from '../util/html_escape';
import { spliceIntoHead, stripStaleHeadSignals } from './head_splice';

export function injectEntityHead(spaShellHtml: string, headTags: string): string {
	return spliceIntoHead(
		stripStaleHeadSignals(spaShellHtml, ['title', 'social', 'canonical', 'jsonLd']),
		headTags,
	);
}

/// The 404 body: the app's own shell, told not to be indexed.
///
/// Every share Lambda used to answer its own hand-written sentence here --
/// `<p>This link isn't available.</p>`, unstyled, unlocalized, no navigation,
/// five slightly different spellings of it. A reader never saw one, because the
/// distribution then carried a `custom_error_response` mapping 404 to the SPA
/// shell (decisions § 1022) -- so the designed `.notfound-card` rendered and the
/// `noindex` these handlers send was thrown away with the body.
///
/// Returning the shell HERE is what made that mapping redundant, and § 1084
/// then removed it: the distribution maps only 403 today, and
/// `scripts/check_infra_error_responses.mjs` fails the PR if a 404 mapping
/// comes back. So this function is now the ONLY thing that puts a designed,
/// localized card in front of a reader who follows a dead share link, and the
/// `noindex` survives because nothing rewrites the body any more.
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
	if (typeof spaShellHtml !== 'string' || !/<\/head(?=[\s/>])[^>]*>/i.test(spaShellHtml)) {
		return `<!doctype html><html lang="en"><head><meta charset="utf-8">${head}</head><body></body></html>`;
	}
	return injectEntityHead(spaShellHtml, head);
}
