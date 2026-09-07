// Every cross-platform fail-closed deploy gate's env-var NAME, on both
// platforms at once. Invocation:
//   npx tsx --test src/lib/safety/deploy_gate_names.test.ts
//
// The convention every mobile gate's header states is "web spells it
// `PUBLIC_<X>`, mobile drops the web-only `PUBLIC_` prefix". It is a real
// operational claim rather than a style one: an operator flipping a gate for a
// release reads one name and sets the other, so a pair whose STEMS differ means
// they have signed one platform off and not the other, silently, in exactly the
// direction the gate exists to prevent.
//
// Nothing tested it, and it turned out to be false for one of the four. Web
// reads `PUBLIC_WEIGH_IN_ENABLED`; mobile reads `WEIGH_IN_GATE`. The Dart
// header meanwhile named `PUBLIC_WEIGH_IN_GATE`, a variable no file in the repo
// reads or sets, so the one place a reader could have learned about the
// exception told them the opposite (decisions § 1354).
//
// So the exception is DECLARED here and re-measured, rather than the convention
// being weakened to fit it: a gate whose names start agreeing fails as a stale
// exemption, and a fourth gate that quietly breaks the convention fails as a
// new one. The KEYS themselves are read out of the source, never listed — a
// list of names would go stale the same way the header did — and the census
// walks `src/lib` for `*_flag.ts` so a gate this file has never heard of fails
// rather than going unmeasured, which is how `nearby_flag` was found missing
// from the first draft of this very list.
//
// The Dart mirror is `apps/mobile_android/test/deploy_gate_names_test.dart`,
// which makes the same measurement from the other tree.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

/// Web flag module -> its Dart counterpart. Both halves of each pair are
/// registered in the syncer table; the point here is the NAMES they read.
const GATES: readonly { web: string; dart: string }[] = [
	{ web: 'src/lib/safety/off_route_flag.ts', dart: '../mobile_android/lib/off_route_flag.dart' },
	{ web: 'src/lib/runs/weigh_in_flag.ts', dart: '../mobile_android/lib/weigh_in_flag.dart' },
	{ web: 'src/lib/social/nearby_flag.ts', dart: '../mobile_android/lib/nearby_flag.dart' },
	{
		web: 'src/lib/training/adaptive_fitness_flag.ts',
		dart: '../mobile_android/lib/adaptive_fitness_flag.dart',
	},
];

/// Gates that exist on web and nowhere else, so there is no second name to
/// compare. Each is re-measured rather than trusted: the Dart tree is checked
/// for a module of the same basename, so the day a mobile half lands the entry
/// fails instead of quietly exempting a real pair.
const WEB_ONLY = new Map<string, string>([
	['src/lib/coach/coach_flag.ts', 'the AI coach is a web surface; mobile reaches it through the same API, not through a gate of its own'],
	['src/lib/core/google_auth_flag.ts', 'mobile gates Google sign-in on the presence of GOOGLE_WEB_CLIENT_ID itself, not on a separate flag'],
	['src/lib/routes/route_gen_flag.ts', 'the graph-cycle sidecar is reached from the web route builder only'],
	['src/lib/social/fundraising_flag.ts', 'the fundraising surface is web-canonical with no mobile twin (decisions § 24)'],
	['src/lib/training/cycle_plan_flag.ts', 'cycle_plan has a Dart twin but no mobile SURFACE consumes it yet, so mobile has no gate to name'],
]);

/// The shared parser, not a gate: it reads no env key of its own.
const PARSER = 'src/lib/core/env_flag.ts';

/// Gates whose two names do NOT satisfy the convention, and why. An entry that
/// has stopped being a violation fails, so this can only shrink.
const KNOWN_EXCEPTIONS = new Map<string, string>([
	[
		'src/lib/runs/weigh_in_flag.ts',
		'the stems differ, not just the prefix: PUBLIC_WEIGH_IN_ENABLED against ' +
			'WEIGH_IN_GATE. Both headers now say so outright (decisions § 1354).',
	],
]);

function read(path: string): string {
	return readFileSync(resolve(path), 'utf-8');
}

/// The `PUBLIC_*` env key a web flag module reads.
export function webKey(source: string): string | null {
	return /\benv\.(PUBLIC_[A-Z0-9_]+)\b/.exec(source)?.[1] ?? null;
}

/// The dart-define / dotenv key a Dart flag module reads, taken from the `k…EnvKey`
/// constant rather than from a `dotenv.env[...]` subscript, because the modules
/// deliberately name the key once and subscript with the constant.
export function dartKey(source: string): string | null {
	return /const String k\w*EnvKey = '([A-Z0-9_]+)';/.exec(source)?.[1] ?? null;
}

test('the key readers find the key in every gate module on both platforms', () => {
	// Without this, a reader that stopped matching would report every gate as
	// having no key and the convention test below would pass vacuously.
	for (const gate of GATES) {
		assert.ok(webKey(read(gate.web)), `no PUBLIC_ key found in ${gate.web}`);
		assert.ok(dartKey(read(gate.dart)), `no k…EnvKey constant found in ${gate.dart}`);
	}
});

test('every deploy gate either follows the dropped-prefix convention or is a declared exception', () => {
	for (const gate of GATES) {
		const web = webKey(read(gate.web));
		const dart = dartKey(read(gate.dart));
		const follows = web === `PUBLIC_${dart}`;
		const exception = KNOWN_EXCEPTIONS.get(gate.web);
		if (exception) {
			assert.equal(
				follows,
				false,
				`${gate.web} reads ${web} and ${gate.dart} reads ${dart}, which now DO satisfy ` +
					`the convention — delete the KNOWN_EXCEPTIONS entry, which is cover for ` +
					`nothing and hides the next one.`,
			);
			continue;
		}
		assert.ok(
			follows,
			`${gate.web} reads ${web} but ${gate.dart} reads ${dart}. The convention is that ` +
				`mobile drops the web-only PUBLIC_ prefix and nothing else, so an operator who ` +
				`sets one has set both. If the difference is deliberate, declare it in ` +
				`KNOWN_EXCEPTIONS with the reason and say so in both headers — an undeclared ` +
				`one means a gate signed off on one platform and open on the other.`,
		);
	}
});

test('a name the repo reads nowhere is never stated as the counterpart', () => {
	// The defect this whole file came from: the Dart header named
	// `PUBLIC_WEIGH_IN_GATE`, which no file reads or sets, so the exception was
	// documented as its opposite. Every `PUBLIC_*` token appearing in a gate
	// module on either platform must be a key some web gate actually reads.
	const live = new Set(GATES.map((g) => webKey(read(g.web))));
	for (const gate of GATES) {
		for (const source of [gate.web, gate.dart]) {
			for (const m of read(source).matchAll(/\bPUBLIC_[A-Z0-9_]+\b/g)) {
				assert.ok(
					live.has(m[0]),
					`${source} names ${m[0]}, which no web gate module reads. A counterpart name ` +
						`that exists nowhere is worse than none: it reads as instructions.`,
				);
			}
		}
	}
});

test('the gate census names every web flag module in the tree', () => {
	// GATES is a list, so it can go stale — a fourth gate would simply not be
	// measured. This walks for `*_flag.ts` and fails on one the list omits, the
	// same population rule `core/env_flag.test.ts` applies to the parse.
	const found: string[] = [];
	const walk = (dir: string): void => {
		for (const e of readdirSync(resolve(dir), { withFileTypes: true })) {
			if (e.isDirectory()) walk(`${dir}/${e.name}`);
			else if (/_flag\.ts$/.test(e.name)) found.push(`${dir}/${e.name}`);
		}
	};
	walk('src/lib');
	assert.ok(
		found.length >= GATES.length + WEB_ONLY.size + 1,
		'the flag-module walk stopped matching — a walk that finds nothing reports no gaps',
	);
	const listed = new Set(GATES.map((g) => g.web));
	for (const path of found) {
		if (path === PARSER || listed.has(path)) continue;
		assert.ok(
			WEB_ONLY.has(path),
			`${path} is a deploy gate that GATES does not carry, so its env-var name is ` +
				`compared with nothing. Add it with its Dart counterpart, or declare it in ` +
				`WEB_ONLY with the reason it has none.`,
		);
	}
	// The web-only claim, re-measured: a Dart module of the same basename means
	// the gate has grown a second name and the entry is now hiding a real pair.
	for (const [path, reason] of WEB_ONLY) {
		assert.ok(found.includes(path), `WEB_ONLY names ${path}, which is not a flag module`);
		assert.ok(reason.length > 20, `WEB_ONLY's reason for ${path} says nothing`);
		const dart = join('../mobile_android/lib', path.split('/').pop()!.replace(/\.ts$/, '.dart'));
		assert.equal(
			existsSync(resolve(dart)),
			false,
			`${path} is declared web-only but ${dart} now exists — compare the two names ` +
				`in GATES instead of exempting the gate.`,
		);
	}
});
