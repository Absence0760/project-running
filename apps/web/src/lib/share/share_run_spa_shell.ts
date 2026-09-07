/// Inject per-run `<head>` meta tags into a SvelteKit SPA-shell HTML
/// template at request time. Pure -- separated from the Lambda
/// handler so the substitution logic is unit-testable without an
/// AWS event in scope.
///
/// The strategy: at deploy time the share-run Lambda's bundler embeds
/// `apps/web/build/200.html` -- adapter-static's SPA fallback, served for
/// any non-prerendered route -- as a string; per request the Lambda calls
/// `injectShareRunMeta` to splice in the run-specific tags. The strip and
/// splice steps live once, in head_splice.ts.
///
/// A stale copy of any signal this head supplies would sit alongside the
/// per-run one, and unfurlers disagree about which of two they read (Slackbot
/// picks the first; Twitterbot the last), so each is stripped before the
/// splice. What the shell actually carries today is measured, not assumed: see
/// spa_shell_head_signals.test.ts.
///
/// The JSON-LD is the one that has to be decided per call rather than named
/// once. `ShareRunMeta.jsonLd` is optional and the badge share page -- which
/// reuses this shape and this injector -- leaves it unset, so stripping it
/// unconditionally deleted the shell's own node from every badge page and put
/// nothing back. That is the case head_splice.ts takes a signal list FOR; a
/// list fixed at the module level just spelled it in the wrong place.
///
/// Persona-hunt finding Casual #4.

import { renderShareRunHeadTags, type ShareRunMeta } from './share_run_meta';
import { spliceIntoHead, stripStaleHeadSignals, type HeadSignal } from './head_splice';

export function injectShareRunMeta(
	spaShellHtml: string,
	meta: ShareRunMeta,
): string {
	const newTags = renderShareRunHeadTags(meta);
	const signals: HeadSignal[] = ['title', 'social', 'canonical'];
	if (meta.jsonLd) signals.push('jsonLd');
	return spliceIntoHead(stripStaleHeadSignals(spaShellHtml, signals), newTags);
}
