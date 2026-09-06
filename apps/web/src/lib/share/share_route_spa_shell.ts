/// Inject per-route `<head>` meta tags into a SvelteKit SPA-shell HTML
/// template at request time. Pure -- separated from the Lambda handler
/// so the substitution logic is unit-testable without an AWS event in
/// scope. Mirror of share_run_spa_shell.ts.
///
/// The strategy: at deploy time the share-route Lambda's bundler embeds
/// `apps/web/build/200.html` -- adapter-static's SPA fallback, served for
/// any non-prerendered route -- as a string; per request the Lambda calls
/// `injectShareRouteMeta` to splice in the route-specific tags. The strip and
/// splice steps live once, in head_splice.ts.
///
/// The route head carries all four signals -- title, social meta, a
/// `<link rel="canonical">` and a JSON-LD `<script>` -- so all four are named
/// here, and a stale copy of any of them in the shell would sit alongside the
/// per-route one (a duplicate canonical or a second WebPage node confuses
/// crawlers). What the shell actually carries today is measured, not assumed:
/// see spa_shell_head_signals.test.ts.

import {
	renderShareRouteHeadTags,
	type ShareRouteHead,
} from './share_route_meta';
import { spliceIntoHead, stripStaleHeadSignals } from './head_splice';

export function injectShareRouteMeta(
	spaShellHtml: string,
	head: ShareRouteHead,
): string {
	const newTags = renderShareRouteHeadTags(head);
	return spliceIntoHead(
		stripStaleHeadSignals(spaShellHtml, ['title', 'social', 'canonical', 'jsonLd']),
		newTags,
	);
}
