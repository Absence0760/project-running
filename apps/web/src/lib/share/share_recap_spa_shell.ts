/// Inject per-recap `<head>` meta tags into a SvelteKit SPA-shell HTML
/// template at request time. Pure -- separated from the Lambda handler so
/// the substitution is unit-testable without an AWS event in scope.
///
/// Two signals, not four, and that asymmetry is the reason head_splice.ts
/// takes a signal list rather than doing everything: a recap head emits
/// neither a canonical nor a JSON-LD block, so stripping those would delete
/// whatever the shell itself carries and put nothing back.

import { renderShareRecapHeadTags, type ShareRecapMeta } from './share_recap_meta';
import { spliceIntoHead, stripStaleHeadSignals } from './head_splice';

export function injectShareRecapMeta(
	spaShellHtml: string,
	meta: ShareRecapMeta,
): string {
	const newTags = renderShareRecapHeadTags(meta);
	return spliceIntoHead(stripStaleHeadSignals(spaShellHtml, ['title', 'social']), newTags);
}
