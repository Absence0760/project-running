/// Inject per-recap `<head>` meta tags into a SvelteKit SPA-shell HTML
/// template at request time. Pure -- separated from the Lambda handler so
/// the substitution is unit-testable without an AWS event in scope.
///
/// Three signals, not four, and that asymmetry is the reason head_splice.ts
/// takes a signal list rather than doing everything: a recap head emits no
/// JSON-LD block, so stripping that would delete whatever node the shell
/// carries and put nothing back.
///
/// The canonical is not in that class and used to be treated as though it
/// were. `renderShareRecapHeadTags` has emitted a self-referential canonical
/// since decisions § 1090; leaving `canonical` out of this list meant the
/// shell's own was kept and the recap's spliced in after it, and a page
/// offering two conflicting `rel=canonical` links has neither honoured --
/// which is precisely the consolidation § 1090 added the tag to get.

import { renderShareRecapHeadTags, type ShareRecapMeta } from './share_recap_meta';
import { spliceIntoHead, stripStaleHeadSignals } from './head_splice';

export function injectShareRecapMeta(
	spaShellHtml: string,
	meta: ShareRecapMeta,
): string {
	const newTags = renderShareRecapHeadTags(meta);
	return spliceIntoHead(
		stripStaleHeadSignals(spaShellHtml, ['title', 'social', 'canonical']),
		newTags,
	);
}
