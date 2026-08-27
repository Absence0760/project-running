#!/usr/bin/env node
// Guardrail: the four `pnpm.overrides` entries are supply-chain pins, and they
// are still both DECLARED and IN EFFECT.
//
// They are not preferences. Each one nudges a transitive dependency off a
// version with a live advisory that its own parent has not bumped past —
// `cookie` (GHSA-pxg6-pf52-xh8x), `devalue` (GHSA-77vg-94rm-hx3p), `undici`
// (the five SOCKS5/cookie/websocket/cache CVEs fixed in 7.28.0) and
// `brace-expansion` (GHSA-mh99-v99m-4gvg). The rationale for each lives in
// root package.json's `_overrides_rationale`.
//
// Why a guard rather than a shrug. Dependabot PR #812 (@types/node 26.1.2 ->
// 26.2.0) regenerated pnpm-lock.yaml and dropped the top-level `overrides:`
// block entirely. Every job running `pnpm install --frozen-lockfile` then died
// with ERR_PNPM_LOCKFILE_CONFIG_MISMATCH before a single test ran — 17 red
// checks (14 Playwright shards, the live-hub lane, the SSO lane), each naming
// pnpm and none naming what changed. That is the LOUD failure, and it is not
// the one worth building for: it cost a red CI cycle to diagnose and then
// fixed itself. The quiet one is the reason this exists — any path where the
// lockfile and the declaration diverge WITHOUT a frozen install reading them
// (a plain `pnpm install`, a hand-edit, a second resolver) leaves the pins
// declared and not applied, and the vulnerable transitive versions come back
// with nothing to say so. A pin that can go missing unnoticed is not a pin.
//
// Four checks, in the order a reader wants them:
//
//   1. `pnpm.overrides` is present and non-empty. A guard over an empty set
//      enforces nothing, which is the vacuous-pass hazard the sibling guards'
//      own comments record.
//   2. pnpm-lock.yaml carries an `overrides:` block, and it matches
//      `pnpm.overrides` key for key. This is exactly what #812 deleted.
//   3. The npm-style top-level `overrides` block matches too, once flattened.
//      The repo carries BOTH declarations and BOTH lockfiles: most CI jobs run
//      `npm ci` off package-lock.json, the Playwright / live-hub / SSO lanes
//      run `pnpm install --frozen-lockfile` off pnpm-lock.yaml. Two resolvers
//      reading two declarations of one security decision must agree, or one
//      half of CI installs a patched tree and the other does not.
//   4. Every version each pin names, in BOTH lockfiles' package trees,
//      satisfies the pin — including nested copies. A lockfile that declares
//      an override and resolved around it is the failure this is really about;
//      the declaration halves above only prove the intent survived.
//
// Two spellings, and which is canonical here. pnpm writes a scoped override
// FLAT — `'@sveltejs/kit>cookie': ^1.0.2` — and npm writes the same thing as a
// nested object under the parent's name. The flat form is canonical in this
// script because it is the only one pnpm ever writes into pnpm-lock.yaml, so
// it is the spelling the frozen-install comparison actually runs against;
// npm's nested block is normalised INTO it for comparison rather than the
// other way round. Everything downstream (target resolution, the tree scan)
// therefore deals with one shape.
//
// pnpm 10 also accepts `overrides` in pnpm-workspace.yaml. Moving them there
// is a legitimate future change, and this guard fails loudly on it rather than
// passing over an empty set — check 1 is what makes that true.
//
// Check-only, deliberately — no `--fix`. `sync_deno_lock.mjs` auto-writes
// because the section it owns is inert (nothing resolves against it) and deno
// canonicalizes the ranges so a hand-edit does not stick. This one is the
// opposite on both counts: the `overrides:` block is load-bearing, and the
// only thing that can rewrite it is a real resolution pass
// (`pnpm install --lockfile-only`), which re-resolves the whole graph and can
// move versions this script never looked at. That is the same class of write
// sync_deno_lock refuses for `remote`/`redirects`. Regenerating a lockfile is
// a human's decision to review, not a guard's to make.
//
// Run: `node scripts/check_pnpm_overrides.mjs` (also `pnpm check:pnpm-overrides`)
// Fix: `pnpm install --lockfile-only`, then commit both lockfiles.
// CI:  the `parity-types` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_pnpm_overrides.test.mjs`

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const PACKAGE_JSON = join(REPO_ROOT, 'package.json');
export const PNPM_LOCK = join(REPO_ROOT, 'pnpm-lock.yaml');
export const NPM_LOCK = join(REPO_ROOT, 'package-lock.json');

export const FIX_COMMAND = 'pnpm install --lockfile-only';

/** @typedef {{ name: string, version: string, where: string }} Resolution */
/** @typedef {{ flat: Map<string, string>, problems: string[] }} FlatOverrides */
/** @typedef {{ major: number, minor: number, patch: number, prerelease: string | null, raw: string }} SemVer */
/** @typedef {{ ok: boolean, reason?: string, unsupported?: undefined }} Decided */
/** @typedef {{ unsupported: true, ok?: undefined, reason?: undefined }} Unsupported */
/** @typedef {Decided | Unsupported} Verdict */
/** @typedef {{ pnpm?: { overrides?: unknown }, overrides?: unknown }} PackageManifest */
/** @typedef {{ packages?: Record<string, unknown> }} NpmLockfile */

/// Strip a YAML scalar's quotes. pnpm quotes a key or value only when it must
/// — `'@sveltejs/kit>cookie'` because of the `@`, `'>=1.2.3'` because a bare
/// `>` opens a folded scalar — so both quoted and bare forms appear.
/** @param {string} value */
function unquote(value) {
	const trimmed = value.trim();
	if (
		(trimmed.startsWith("'") && trimmed.endsWith("'") && trimmed.length > 1) ||
		(trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length > 1)
	) {
		return trimmed.slice(1, -1);
	}
	return trimmed;
}

/// pnpm-lock.yaml's top-level `overrides:` block as a Map, or null when the
/// block is absent. Null and an empty Map are different answers: the first is
/// #812's regression, the second is a block that exists and pins nothing.
///
/// Line-based rather than YAML-parsed because the guard jobs run `node`
/// against a bare checkout with no `npm ci`, so only the stdlib is available —
/// the same constraint check_toolchain_pins.mjs and check_ci_diagnostics.mjs
/// work under.
/**
 * @param {string} lockText
 * @returns {Map<string, string> | null}
 */
export function parseLockOverrides(lockText) {
	const lines = lockText.split('\n');
	for (let i = 0; i < lines.length; i++) {
		if (!/^overrides:\s*$/.test(lines[i])) continue;
		/** @type {Map<string, string>} */
		const found = new Map();
		for (let j = i + 1; j < lines.length; j++) {
			const line = lines[j];
			if (!line.trim()) continue;
			if (!/^\s/.test(line)) break;
			if (line.trimStart().startsWith('#')) continue;
			const m = line.match(/^\s{2}(\S.*?):\s+(\S.*?)\s*$/);
			if (m) found.set(unquote(m[1]), unquote(m[2]));
		}
		return found;
	}
	return null;
}

/// Every `name@version` key in pnpm-lock.yaml's `packages:` section. That
/// section holds one entry per resolved tarball; `snapshots:` re-lists the
/// same versions with peer suffixes, so reading `packages:` counts each
/// resolution exactly once.
/**
 * @param {string} lockText
 * @returns {Resolution[]}
 */
export function parsePnpmResolutions(lockText) {
	const lines = lockText.split('\n');
	/** @type {Resolution[]} */
	const found = [];
	let inside = false;
	for (const line of lines) {
		if (/^packages:\s*$/.test(line)) {
			inside = true;
			continue;
		}
		if (!inside) continue;
		if (line.trim() && !/^\s/.test(line)) break;
		const m = line.match(/^\s{2}(\S.*?):\s*$/);
		if (!m) continue;
		const key = unquote(m[1]);
		const at = key.lastIndexOf('@');
		if (at <= 0) continue;
		found.push({ name: key.slice(0, at), version: key.slice(at + 1), where: 'pnpm-lock.yaml' });
	}
	return found;
}

/// Every resolved package in a package-lock.json, nested copies included. A
/// nested `node_modules/x/node_modules/cookie` is the exact shape an override
/// exists to reach (see `_overrides_rationale`), so the path is walked to its
/// LAST `node_modules/` segment rather than matched at the top level.
/**
 * @param {NpmLockfile | null | undefined} lockJson
 * @returns {Resolution[]}
 */
export function parseNpmResolutions(lockJson) {
	/** @type {Resolution[]} */
	const found = [];
	for (const [path, entry] of Object.entries(lockJson?.packages ?? {})) {
		const at = path.lastIndexOf('node_modules/');
		if (at < 0) continue;
		const name = path.slice(at + 'node_modules/'.length);
		const version = entry && typeof entry === 'object' && 'version' in entry ? entry.version : null;
		if (!name || typeof version !== 'string') continue;
		found.push({ name, version, where: 'package-lock.json' });
	}
	return found;
}

/// An npm-style `overrides` object flattened into pnpm's `parent>child`
/// spelling, so the two declarations become comparable.
/**
 * @param {unknown} overrides
 * @param {string} [prefix]
 * @returns {FlatOverrides}
 */
export function flattenOverrides(overrides, prefix = '') {
	/** @type {Map<string, string>} */
	const flat = new Map();
	/** @type {string[]} */
	const problems = [];
	if (typeof overrides !== 'object' || overrides === null) return { flat, problems };
	for (const [key, value] of Object.entries(/** @type {Record<string, unknown>} */ (overrides))) {
		if (key === '.') {
			problems.push(
				`\`${prefix || '<root>'}\` uses npm's \`"."\` key to pin the parent's own version. ` +
					`pnpm has no spelling for that, so the two declarations cannot be kept equal — ` +
					`express it as a plain dependency bump instead.`,
			);
			continue;
		}
		const path = prefix ? `${prefix}>${key}` : key;
		if (typeof value === 'string') flat.set(path, value);
		else if (value && typeof value === 'object') {
			const nested = flattenOverrides(value, path);
			for (const [k, v] of nested.flat) flat.set(k, v);
			problems.push(...nested.problems);
		} else {
			problems.push(`\`${path}\` has no version range (found \`${JSON.stringify(value)}\`).`);
		}
	}
	return { flat, problems };
}

/// The package a pin applies to, and the parent that scopes it. pnpm reads the
/// LAST `>` as the boundary, and a parent selector may carry its own range
/// (`foo@1>bar`), which is not part of the parent's name.
/**
 * @param {string} key
 * @returns {{ target: string, parent: string | null }}
 */
export function pinTarget(key) {
	const at = key.lastIndexOf('>');
	if (at < 0) return { target: key, parent: null };
	const parent = key.slice(0, at);
	const sep = parent.lastIndexOf('@');
	return { target: key.slice(at + 1), parent: sep > 0 ? parent.slice(0, sep) : parent };
}

/**
 * @param {string} value
 * @returns {SemVer | null}
 */
export function parseVersion(value) {
	const m = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/.exec(value);
	if (!m) return null;
	return { major: +m[1], minor: +m[2], patch: +m[3], prerelease: m[4] ?? null, raw: value };
}

/**
 * @param {SemVer} a
 * @param {SemVer} b
 */
function compare(a, b) {
	return a.major - b.major || a.minor - b.minor || a.patch - b.patch;
}

/// Does `version` satisfy `range`? Only the comparator forms the pins actually
/// use are implemented — an unrecognised range returns `unsupported`, which
/// the caller reports as a failure. Answering "satisfied" over a range this
/// cannot read would be the vacuous pass the whole file is written against.
/**
 * @param {string} version
 * @param {string} range
 * @returns {Verdict}
 */
export function satisfies(version, range) {
	const v = parseVersion(version);
	if (!v) return { ok: false, reason: `\`${version}\` is not a plain semver version` };
	const m = /^(\^|~|>=|=)?\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)$/.exec(range.trim());
	if (!m) return { unsupported: true };
	const base = parseVersion(m[2]);
	if (!base) return { unsupported: true };
	// A prerelease compares by rules this deliberately does not implement, so
	// either side carrying one narrows to exact equality rather than guessing.
	if (v.prerelease || base.prerelease) return { ok: v.raw === base.raw };
	switch (m[1] ?? '=') {
		case '=':
			return { ok: compare(v, base) === 0 };
		case '>=':
			return { ok: compare(v, base) >= 0 };
		case '~':
			return { ok: v.major === base.major && v.minor === base.minor && v.patch >= base.patch };
		case '^':
			if (base.major > 0) return { ok: v.major === base.major && compare(v, base) >= 0 };
			if (base.minor > 0) return { ok: v.major === 0 && v.minor === base.minor && v.patch >= base.patch };
			return { ok: compare(v, base) === 0 };
		default:
			return { unsupported: true };
	}
}

/** @param {Map<string, string>} map */
function formatMap(map) {
	return [...map.entries()]
		.sort((a, b) => a[0].localeCompare(b[0]))
		.map(([k, v]) => `    ${k}: ${v}`)
		.join('\n');
}

/**
 * @param {Map<string, string>} expected
 * @param {Map<string, string>} actual
 * @param {string} expectedLabel
 * @param {string} actualLabel
 * @returns {string[]}
 */
function diffMaps(expected, actual, expectedLabel, actualLabel) {
	/** @type {string[]} */
	const lines = [];
	for (const [key, value] of expected) {
		if (!actual.has(key)) lines.push(`    - ${key}: ${value}  (in ${expectedLabel}, missing from ${actualLabel})`);
		else if (actual.get(key) !== value) {
			lines.push(`    ~ ${key}: ${expectedLabel} says ${value}, ${actualLabel} says ${actual.get(key)}`);
		}
	}
	for (const [key, value] of actual) {
		if (!expected.has(key)) lines.push(`    + ${key}: ${value}  (in ${actualLabel}, absent from ${expectedLabel})`);
	}
	return lines;
}

/// Checks 1-3: the pins are declared, and every declaration of them agrees.
/**
 * @param {PackageManifest | null | undefined} pkg
 * @param {string} pnpmLockText
 * @returns {{ errors: string[], ok: string[], declared: Map<string, string> }}
 */
export function checkDeclarations(pkg, pnpmLockText) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	const declaredRaw = pkg?.pnpm?.overrides;
	if (!declaredRaw || typeof declaredRaw !== 'object' || Object.keys(declaredRaw).length === 0) {
		return {
			errors: [
				`root package.json declares no \`pnpm.overrides\`. Either the security pins ` +
					`were removed — in which case delete this guard with them, and record why in ` +
					`decisions.md — or the block moved and this check now enforces nothing.`,
			],
			ok,
			declared: new Map(),
		};
	}

	const { flat: declared, problems } = flattenOverrides(declaredRaw);
	errors.push(...problems.map((p) => `root package.json \`pnpm.overrides\`: ${p}`));
	ok.push(`root package.json declares ${declared.size} pnpm override(s)`);

	const inLock = parseLockOverrides(pnpmLockText);
	if (inLock === null) {
		errors.push(
			`pnpm-lock.yaml has NO top-level \`overrides:\` block, but root package.json ` +
				`declares ${declared.size}:\n${formatMap(declared)}\n` +
				`  Every \`pnpm install --frozen-lockfile\` job aborts on this with ` +
				`ERR_PNPM_LOCKFILE_CONFIG_MISMATCH before it runs anything — and worse, an ` +
				`unfrozen install would simply not apply the pins. A lockfile regenerated by ` +
				`a bot that dropped the block is how this last happened (#812). Regenerate ` +
				`with \`${FIX_COMMAND}\`.`,
		);
	} else if (inLock.size === 0) {
		errors.push(
			`pnpm-lock.yaml's \`overrides:\` block is empty while root package.json declares ` +
				`${declared.size} pin(s). Regenerate with \`${FIX_COMMAND}\`.`,
		);
	} else {
		const drift = diffMaps(declared, inLock, 'package.json pnpm.overrides', 'pnpm-lock.yaml overrides');
		if (drift.length) {
			errors.push(
				`pnpm-lock.yaml's \`overrides:\` block has drifted from root package.json's ` +
					`\`pnpm.overrides\`:\n${drift.join('\n')}\n  Regenerate with \`${FIX_COMMAND}\`.`,
			);
		} else {
			ok.push(`pnpm-lock.yaml's overrides block matches all ${declared.size} of them`);
		}
	}

	// The npm-style block is compared against pnpm's, not the reverse: pnpm's
	// flat spelling is the one both lockfiles' comparisons are expressed in.
	const npmStyle = flattenOverrides(pkg?.overrides);
	errors.push(...npmStyle.problems.map((p) => `root package.json \`overrides\`: ${p}`));
	if (npmStyle.flat.size === 0) {
		errors.push(
			`root package.json declares \`pnpm.overrides\` but no top-level \`overrides\`. ` +
				`Most CI jobs install with \`npm ci\` off package-lock.json, which reads only ` +
				`the npm-style block — so the pins would apply to the pnpm lanes and to nothing ` +
				`else. Declare both.`,
		);
	} else {
		const drift = diffMaps(declared, npmStyle.flat, 'pnpm.overrides', 'overrides (npm)');
		if (drift.length) {
			errors.push(
				`root package.json's two override declarations disagree, so npm and pnpm would ` +
					`pin different things:\n${drift.join('\n')}\n` +
					`  npm spells a scoped override as a nested object under the parent ` +
					`(\`"@sveltejs/kit": { "cookie": "^1.0.2" }\`) where pnpm spells it flat ` +
					`(\`"@sveltejs/kit>cookie": "^1.0.2"\`); both are shown flattened above.`,
			);
		} else {
			ok.push(`root package.json's npm-style \`overrides\` block agrees with \`pnpm.overrides\``);
		}
	}

	return { errors, ok, declared };
}

/// Check 4: the pins took effect. A declared override that the tree resolved
/// around is the whole point — the declaration halves prove intent, this
/// proves outcome.
/**
 * @param {Map<string, string>} declared
 * @param {Resolution[]} resolutions
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkResolutions(declared, resolutions) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	if (resolutions.length === 0) {
		return {
			errors: ['no resolved packages found in either lockfile — the parser matched nothing, so this check enforces nothing.'],
			ok,
		};
	}

	// One pinned NAME can be named by several pins (a bare pin plus a scoped
	// one), and both constrain the same set of resolved copies. Grouping by
	// target keeps the tree scan to one pass and reports a bad copy once.
	/** @type {Map<string, { key: string, range: string, parent: string | null }[]>} */
	const byTarget = new Map();
	for (const [key, range] of declared) {
		const { target, parent } = pinTarget(key);
		const pins = byTarget.get(target) ?? [];
		pins.push({ key, range, parent });
		byTarget.set(target, pins);
	}

	const present = new Set(resolutions.map((r) => r.name));

	for (const [target, pins] of [...byTarget.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
		const copies = resolutions.filter((r) => r.name === target);
		if (copies.length === 0) {
			errors.push(
				`\`${target}\` is pinned by ${pins.map((p) => `\`${p.key}\``).join(', ')} but appears ` +
					`in neither lockfile's package tree. Either the dependency is gone and the ` +
					`override should go with it, or the lockfile parser stopped matching and this ` +
					`pin is now checked against nothing.`,
			);
			continue;
		}
		let clean = true;
		for (const pin of pins) {
			if (pin.parent && !present.has(pin.parent)) {
				clean = false;
				errors.push(
					`\`${pin.key}\` scopes a pin to \`${pin.parent}\`, which is in neither lockfile. ` +
						`The pin reaches nothing; drop it or fix the parent's name.`,
				);
			}
			/** @type {{ copy: Resolution, reason: string | undefined }[]} */
			const bad = [];
			let unsupported = false;
			for (const copy of copies) {
				const verdict = satisfies(copy.version, pin.range);
				if (verdict.unsupported) {
					unsupported = true;
					break;
				}
				if (!verdict.ok) bad.push({ copy, reason: verdict.reason });
			}
			if (unsupported) {
				clean = false;
				errors.push(
					`\`${pin.key}: ${pin.range}\` uses a range form this guard cannot evaluate, so ` +
						`it cannot say whether the pin took effect. Use a caret, tilde, \`>=\` or ` +
						`exact version, or teach \`satisfies\` the new form — do not leave a pin ` +
						`that reports success without being checked.`,
				);
				continue;
			}
			if (bad.length) {
				clean = false;
				const detail = bad
					.map(({ copy, reason }) => `    ${copy.name}@${copy.version} (${copy.where})${reason ? ` — ${reason}` : ''}`)
					.join('\n');
				errors.push(
					`\`${pin.key}\` pins \`${pin.range}\`, but the lockfiles resolved ${bad.length} ` +
						`copy/copies outside it:\n${detail}\n` +
						`  The override is declared and NOT in effect, which is the failure mode a ` +
						`frozen install cannot see. Regenerate with \`${FIX_COMMAND}\`.`,
				);
			}
		}
		if (clean) {
			const versions = [...new Set(copies.map((c) => c.version))].sort();
			ok.push(
				`${target} resolves to ${versions.join(', ')} across ${copies.length} copy/copies, ` +
					`satisfying ${pins.map((p) => p.range).join(' + ')}`,
			);
		}
	}

	return { errors, ok };
}

/**
 * @param {PackageManifest | null | undefined} pkg
 * @param {string} pnpmLockText
 * @param {NpmLockfile | null | undefined} npmLockJson
 */
export function checkAll(pkg, pnpmLockText, npmLockJson) {
	const declarations = checkDeclarations(pkg, pnpmLockText);
	const resolutions = [...parsePnpmResolutions(pnpmLockText), ...parseNpmResolutions(npmLockJson)];
	const effect = checkResolutions(declarations.declared, resolutions);
	return {
		errors: [...declarations.errors, ...effect.errors],
		ok: [...declarations.ok, ...effect.ok],
		declared: declarations.declared,
		resolutions,
	};
}

function main() {
	const { errors, ok, declared, resolutions } = checkAll(
		JSON.parse(readFileSync(PACKAGE_JSON, 'utf-8')),
		readFileSync(PNPM_LOCK, 'utf-8'),
		JSON.parse(readFileSync(NPM_LOCK, 'utf-8')),
	);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);

	if (errors.length > 0) {
		console.error(`\n${errors.length} pnpm override problem(s). Fix: \`${FIX_COMMAND}\`, then commit both lockfiles.`);
		return 1;
	}
	console.log(
		`\n${declared.size} override(s) declared in package.json, recorded in pnpm-lock.yaml, ` +
			`and honoured by every one of the ${resolutions.length} resolved package entries across both lockfiles.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
