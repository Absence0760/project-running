import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Guard-rail: a `/share/<x>` route only unfurls in production if THREE
 * independent places agree it exists — the SvelteKit route, a CloudFront
 * behaviour sending the path at a Lambda, and (for the shared entity Lambda)
 * a branch in its dispatcher. Nothing breaks locally when they disagree: the
 * dev server runs the PageLoad, so the page looks finished while prod quietly
 * serves the empty SPA shell to every crawler and link-unfurler.
 *
 * That is exactly how `/share/session/[id]` + `/share/workout/[id]` shipped —
 * real public routes, real inline heads, no dispatcher, no behaviour, no
 * canonical — and round 11 could only write the gap down (seo.md) rather than
 * detect it. These checks detect it.
 */

const __dirname = resolve(new URL('.', import.meta.url).pathname);
const shareRoutesRoot = resolve(__dirname, '../../routes/share');
const repoRoot = resolve(__dirname, '../../../../..');
const terraform = readFileSync(
	resolve(repoRoot, 'infra/modules/web-stack/main.tf'),
	'utf-8',
);
const dispatcher = readFileSync(
	resolve(repoRoot, 'apps/web/lambda/share-entity/src/index.ts'),
	'utf-8',
);

/// `run`, `route`, `session`, … — one per `src/routes/share/<x>/` directory.
const shareSegments = readdirSync(shareRoutesRoot, { withFileTypes: true })
	.filter((e) => e.isDirectory())
	.map((e) => e.name)
	.sort();

/// `{ "/share/run/*": "lambda-share-run", … }` from the CloudFront behaviours.
function behaviourOrigins(): Map<string, string> {
	const out = new Map<string, string>();
	const re =
		/path_pattern\s*=\s*"(\/share\/[^"]+)"[\s\S]{0,200}?target_origin_id\s*=\s*"([^"]+)"/g;
	for (const m of terraform.matchAll(re)) out.set(m[1], m[2]);
	return out;
}

test('every /share/<x> route is routed to a Lambda by CloudFront', () => {
	const origins = behaviourOrigins();
	assert.ok(shareSegments.length > 0, 'no /share routes found');
	const unrouted = shareSegments.filter((seg) => !origins.has(`/share/${seg}/*`));
	assert.deepEqual(
		unrouted,
		[],
		`these /share routes have no CloudFront behaviour, so prod serves them the SPA ` +
			`shell and an unfurler gets no title, description, or image: ${unrouted.join(', ')}. ` +
			'Add a behaviour in infra/modules/web-stack/main.tf (and a dispatcher branch if it ' +
			'belongs to the shared share-entity Lambda).',
	);
});

test('every path sent to the share-entity Lambda has a dispatcher branch', () => {
	const entityPaths = [...behaviourOrigins()]
		.filter(([, origin]) => origin === 'lambda-share-entity')
		.map(([pattern]) => pattern.replace(/\/\*$/, ''));
	assert.ok(entityPaths.length >= 6, 'the share-entity behaviour set lost paths');
	// The dispatcher's ROUTES regexes are written as
	// /^\/share\/session\/([^/]+)\/?$/, so the path prefix appears with its
	// slashes escaped. Strip the backslashes out of the haystack rather than
	// adding them to the needle: hand-rolling the escape is what CodeQL flags
	// (an escaper that ignores `\` itself is incomplete), and normalising the
	// source is both lossless for a prefix search and immune to however the
	// dispatcher happens to spell its separators.
	const flattened = dispatcher.replaceAll('\\', '');
	const missing = entityPaths.filter((p) => !flattened.includes(p));
	assert.deepEqual(
		missing,
		[],
		`CloudFront sends these paths to the share-entity Lambda but its ROUTES table has no ` +
			`branch for them, so every request falls through to the JSON 404: ${missing.join(', ')}.`,
	);
});

test('every share-entity branch renders through a build/render meta pair', () => {
	// A branch that hand-rolled its head string would sidestep the escaping
	// guard in share_head_escaping.test.ts, which only knows the renderers.
	const branches = [...dispatcher.matchAll(/\/\^\\\/share\\\/(\w+)\\\//g)].map((m) => m[1]);
	assert.ok(branches.length >= 6, `expected >=6 dispatcher branches, found ${branches.length}`);
	for (const entity of branches) {
		const cap = entity[0].toUpperCase() + entity.slice(1);
		assert.match(
			dispatcher,
			new RegExp(`buildShare${cap}Head\\(`),
			`the /share/${entity} branch does not call buildShare${cap}Head`,
		);
		assert.match(
			dispatcher,
			new RegExp(`renderShare${cap}HeadTags\\(`),
			`the /share/${entity} branch does not call renderShare${cap}HeadTags — a hand-rolled ` +
				'head string would escape the share_head_escaping guard',
		);
	}
});
