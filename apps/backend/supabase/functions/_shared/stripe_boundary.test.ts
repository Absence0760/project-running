import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

// The Stripe SDK's declarations bind only through `_shared/stripe.ts`, and
// only because of the `@ts-types` directive in it — esm.sh rewrites stripe's
// ambient `declare module 'stripe'` to name its own declaration file's URL,
// which the runtime specifier is not, so an import straight from the URL
// resolves to `any` and every Stripe call under it is checked against nothing
// (decisions § 765).
//
// Two halves, and neither can do the other's job:
//
//   - a COLLAPSE back to `any` is invisible to a source grep, because the
//     import text does not change. That half is a compile-time assertion
//     inside `stripe.ts` itself, which the `deno check` lane runs.
//   - a NEW function importing Stripe from the URL is invisible to the
//     compiler, because `any` produces no error anywhere. That is this file.
//
// The version pin is checked here too: the runtime specifier and the
// declaration specifier are two strings naming one package, so they can drift,
// and a mismatch types the tier against a version it does not run.

const FUNCTIONS_ROOT = new URL('../', import.meta.url);

/// The module every Stripe import must go through, repo-relative to the
/// functions tree.
const BOUNDARY = '_shared/stripe.ts';
const DECLARATIONS = '_shared/stripe_types.d.ts';

const STRIPE_URL = /['"](https:\/\/esm\.sh\/stripe@[^'"]+)['"]/g;
const STRIPE_VERSION = /https:\/\/esm\.sh\/stripe@([0-9][^/?'"]*)/;

/// Every `*.ts` under the functions tree, repo-relative to it.
async function tsFiles(dir = FUNCTIONS_ROOT, prefix = ''): Promise<string[]> {
	const out: string[] = [];
	for await (const entry of Deno.readDir(dir)) {
		const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
		if (entry.isDirectory) {
			out.push(...(await tsFiles(new URL(`${entry.name}/`, dir), rel)));
		} else if (entry.name.endsWith('.ts')) {
			out.push(rel);
		}
	}
	return out.sort();
}

Deno.test('only the shared boundary module imports Stripe from a URL', async () => {
	const files = await tsFiles();
	assert(
		files.includes(BOUNDARY),
		`${BOUNDARY} is gone. If the boundary moved, move this guard with it — deleting it ` +
			'leaves nothing watching for a function that imports Stripe straight from esm.sh ' +
			'and gets `any` for it.',
	);

	// The boundary existing as a FILE is not the same as the boundary carrying
	// the import — an emptied one satisfies every `offenders` check below while
	// leaving the tier with no Stripe import to bind declarations to.
	const boundarySrc = await Deno.readTextFile(new URL(BOUNDARY, FUNCTIONS_ROOT));
	assert(
		new RegExp(STRIPE_URL.source).test(boundarySrc),
		`${BOUNDARY} no longer imports Stripe from esm.sh — the pattern this guard hunts ` +
			'matches nothing anywhere, so it would report a clean tree either way',
	);

	const offenders: string[] = [];
	for (const file of files) {
		if (file === BOUNDARY || file === DECLARATIONS) continue;
		const src = await Deno.readTextFile(new URL(file, FUNCTIONS_ROOT));
		for (const [, url] of src.matchAll(STRIPE_URL)) offenders.push(`${file} -> ${url}`);
	}

	assertEquals(
		offenders,
		[],
		'These modules import the Stripe SDK straight from esm.sh. That import resolves to ' +
			`\`any\` — it does not fail, it just stops checking — so import from ${BOUNDARY} ` +
			`instead, which carries the directive that binds the declarations: ${
				offenders.join(', ')
			}`,
	);
});

Deno.test('at least one function still goes through the boundary', async () => {
	// Without this, the guard above passes vacuously the day the last Stripe
	// caller is deleted or renamed, and would go on passing while a new one is
	// written against the URL.
	const files = await tsFiles();
	const importers = [];
	for (const file of files) {
		if (file === BOUNDARY) continue;
		const src = await Deno.readTextFile(new URL(file, FUNCTIONS_ROOT));
		if (/from\s*'[^']*_shared\/stripe\.ts'/.test(src)) importers.push(file);
	}
	assert(
		importers.length > 0,
		`nothing imports ${BOUNDARY} any more, so the guard above enforces nothing. If the ` +
			'Stripe functions are gone, delete this file and the boundary with them; if they ' +
			'moved, retarget it.',
	);
});

Deno.test('the runtime specifier and the declarations name the same Stripe version', async () => {
	const runtime = await Deno.readTextFile(new URL(BOUNDARY, FUNCTIONS_ROOT));
	const declarations = await Deno.readTextFile(new URL(DECLARATIONS, FUNCTIONS_ROOT));

	const runtimeVersion = runtime.match(STRIPE_VERSION)?.[1];
	const declarationsVersion = declarations.match(STRIPE_VERSION)?.[1];

	assert(
		runtimeVersion,
		`${BOUNDARY} no longer imports an esm.sh stripe URL, so there is no version to pin. ` +
			'If the SDK moved to a different registry, this guard has to move with it.',
	);
	assert(
		declarationsVersion,
		`${DECLARATIONS} no longer imports an esm.sh stripe URL. That file exists only to name ` +
			'the specifier the ambient declaration matches; without it the boundary is `any`.',
	);
	assertEquals(
		declarationsVersion,
		runtimeVersion,
		`the tier runs stripe@${runtimeVersion} and is typed against stripe@${declarationsVersion}. ` +
			'Two strings name one package here, so a bump has to touch both files: the params ' +
			'and responses the compiler checks would otherwise be a different version\'s.',
	);
});

Deno.test('the boundary carries the directive that binds the declarations', async () => {
	// The compile-time half lives in stripe.ts and only the `deno check` lane
	// runs it; this asserts the two pieces it needs are still there, so a tidy-up
	// that drops either one fails here as well as there.
	const src = await Deno.readTextFile(new URL(BOUNDARY, FUNCTIONS_ROOT));
	assert(
		/^\/\/ @ts-types="\.\/stripe_types\.d\.ts"$/m.test(src),
		`${BOUNDARY} has lost its \`@ts-types\` directive. Without it the import resolves to ` +
			'`any` and every Stripe call in the tier stops being checked, silently.',
	);
	assert(
		src.includes('@ts-expect-error'),
		`${BOUNDARY} has lost the \`@ts-expect-error\` assertion that proves the declarations ` +
			'bound. It is the only thing that fails when they collapse back to `any`: a ' +
			'positive assertion cannot, because `any` satisfies every constraint.',
	);
});
