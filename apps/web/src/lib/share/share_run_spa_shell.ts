/// Inject per-run `<head>` meta tags into a SvelteKit SPA-shell HTML
/// template at request time. Pure -- separated from the Lambda
/// handler so the substitution logic is unit-testable without an
/// AWS event in scope.
///
/// The strategy: at deploy time the share-run Lambda's bundler embeds
/// `apps/web/build/index.html` -- adapter-static's SPA fallback, served for
/// any non-prerendered route -- as a string; per request the Lambda calls
/// `injectShareRunMeta` to splice in the run-specific tags. The strip and
/// splice steps live once, in head_splice.ts.
///
/// The run head carries all four signals -- title, social meta, canonical and
/// a JSON-LD block -- so all four are named here; a stale copy of any of them
/// in the shell would sit alongside the per-run one, and unfurlers disagree
/// about which of two they read (Slackbot picks the first; Twitterbot the
/// last). What the shell actually carries today is measured, not assumed: see
/// spa_shell_head_signals.test.ts.
///
/// Persona-hunt finding Casual #4.

import { renderShareRunHeadTags, type ShareRunMeta } from './share_run_meta';
import { spliceIntoHead, stripStaleHeadSignals } from './head_splice';

export function injectShareRunMeta(
	spaShellHtml: string,
	meta: ShareRunMeta,
): string {
	const newTags = renderShareRunHeadTags(meta);
	return spliceIntoHead(
		stripStaleHeadSignals(spaShellHtml, ['title', 'social', 'canonical', 'jsonLd']),
		newTags,
	);
}
