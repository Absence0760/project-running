/// Inject per-recap `<head>` meta tags into a SvelteKit SPA-shell HTML
/// template at request time. Pure — separated from the Lambda handler so
/// the substitution is unit-testable without an AWS event in scope.
/// Mirrors share_run_spa_shell.ts exactly.

import { renderShareRecapHeadTags, type ShareRecapMeta } from './share_recap_meta';

export function injectShareRecapMeta(
	spaShellHtml: string,
	meta: ShareRecapMeta,
): string {
	const newTags = renderShareRecapHeadTags(meta);
	let out = spaShellHtml;
	out = out.replace(/<title>[\s\S]*?<\/title>/i, '');
	out = out.replace(
		/<meta\s+(?:property|name)="(?:og:[^"]+|twitter:[^"]+|description)"[^>]*>/gi,
		'',
	);
	const insertedAt = out.search(/<\/head>/i);
	if (insertedAt === -1) return out;
	return out.slice(0, insertedAt) + newTags + '\n' + out.slice(insertedAt);
}
