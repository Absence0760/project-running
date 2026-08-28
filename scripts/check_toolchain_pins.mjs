#!/usr/bin/env node
// Guardrail: every toolchain the build installs is pinned, and every workflow
// installs the same one. Two toolchains, checked with the same policy but
// against different sources of truth:
//
//   Flutter — every `subosito/flutter-action` step pins an explicit version,
//     and all of them agree with each other. There is no in-repo file that
//     resolves the SDK, so the workflows ARE the source of truth.
//   melos  — every `dart pub global activate melos` pins a version, and all of
//     them agree with `pubspec.lock`. Here a source of truth DOES exist, so
//     the workflows are checked against it rather than against each other:
//     `pub global activate` ignores the workspace entirely, so without this
//     CI can run a different melos than `dart run melos` resolves locally.
//     This mirrors check_watch_ble_uuids.mjs, which reads the firmware's own
//     table rather than transcribing it.
//   defmt-print — every `cargo install defmt-print` pins an EXACT version (no
//     caret or range), all of them agree, and each one's `actions/cache` key
//     carries that same version. Like Flutter and unlike melos, no in-repo
//     file resolves it: it is a host-side CLI, not a firmware dependency, so
//     it is absent from apps/custom_watch/Cargo.lock and self-consistency is
//     the honest ceiling. The cache-key half is not decoration — the install
//     step is `command -v defmt-print || cargo install ...`, so a cache key
//     that does not move when the version does would keep restoring the old
//     binary and the pin would never run. That is not hypothetical: under the
//     old `^1.1` the key was `defmt-print-1.1-<os>` and never changed, so CI
//     had been serving a cached binary whose provenance the config could not
//     express (run 31623789083 shows the cache hit and `command -v` winning,
//     with `cargo install` never executing).
//
// Why this exists: decisions.md § 595. Each of those steps was SHA-pinned but
// took only `channel: stable`, so the SDK itself floated. Flutter 3.47.0
// (Dart 3.13) published 51 minutes after main's last green run, the next PR
// inherited it, and two new `unawaited_return_in_try_block` warnings failed
// `dart analyze` on code nobody had touched — pointing the blame at that PR
// rather than at the toolchain that moved underneath it.
//
// The version now lives in each workflow's top-level `env.FLUTTER_VERSION`.
// That dedupes the six call sites inside ci.yml, but a workflow-level `env`
// is per-FILE — it cannot span ci.yml, release-android.yml and release-ios.yml,
// and those three must agree or a release binary is built on an SDK that CI
// never validated. A composite action would have collapsed all three to one
// literal, but Dependabot's github-actions ecosystem only scans
// `.github/workflows` plus a ROOT `action.yml`, so moving the pinned
// `subosito/flutter-action@<sha>` into `.github/actions/` would have quietly
// ended SHA updates for it. Three declarations plus this check keeps both
// properties.
//
//   GitHub Actions — every `uses:` reference naming a third-party action pins
//     a 40-character commit SHA and carries the trailing `# vN` comment that
//     makes it readable (conventions.md § GitHub Actions). A tag is mutable:
//     the publisher can move `@v1` onto anything, and it then runs with this
//     repo's GITHUB_TOKEN. Local `uses: ./…` references are the repo's own
//     files and need no pin.
//
//     **Commented-out lines are read too**, and that is the point rather than
//     an edge case. `apple-actions/upload-testflight-build@v1` sat on a
//     mutable tag inside release-ios.yml's commented TestFlight block through
//     the whole pin sweep that moved every live reference to a SHA — written
//     off as dead code precisely because nothing looked at it. It is not
//     dead; it is what someone uncomments on the day they first ship to
//     TestFlight. A guard that skips comments would have re-created the
//     blind spot it exists to close.
//
// The vacuous-pass case is checked for all of them: if the action is renamed,
// or the activate line reworded, this fails rather than reporting success over
// an empty set. A guard that inspects nothing enforces nothing.
//
// Run: `node scripts/check_toolchain_pins.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_toolchain_pins.test.mjs`

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseSteps } from './check_ci_diagnostics.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WORKFLOW_DIR = join(REPO_ROOT, '.github', 'workflows');
// Composite actions are the one place a third-party `uses:` can hide from
// Dependabot entirely — its github-actions ecosystem scans `.github/workflows`
// plus a ROOT action.yml and nothing else (§ 595) — so an unpinned reference
// here would never be updated either. Read for the pin check only; the three
// toolchain checks below are about what the WORKFLOWS install.
export const ACTION_DIR = join(REPO_ROOT, '.github', 'actions');
export const LOCKFILE = join(REPO_ROOT, 'pubspec.lock');

const ACTION = 'subosito/flutter-action@';
const ENV_KEY = 'FLUTTER_VERSION';
const ACTIVATE = 'dart pub global activate melos';
const CARGO_INSTALL = 'cargo install defmt-print';
const EXACT_VERSION = /^\d+\.\d+\.\d+$/;
const COMMIT_SHA = /^[0-9a-f]{40}$/;
// `owner/repo` or `owner/repo/path`, then `@ref`, then an optional trailing
// comment. Anchored so a `uses:` inside prose cannot match.
const ACTION_USES = /^[\s#]*(?:-\s+)?uses:\s*(\S+)\s*(?:#\s*(\S.*?))?\s*$/;
const ACTION_REF = /^([\w][\w.-]*(?:\/[\w.-]+)+)@(\S+)$/;

/** @typedef {{ name: string, text: string }} WorkflowFile */
/** @typedef {{ line: number, version: string | null }} VersionedLine */
/** @typedef {{ error: string, version?: undefined } | { error?: undefined, version: string }} ResolvedFlutter */
/** @typedef {{ line: number, ref: string, comment: string | null, commented: boolean, local: true }} LocalActionUse */
/** @typedef {{ line: number, ref: string, comment: string | null, commented: boolean, local: false, action: string, gitRef: string }} RemoteActionUse */
/** @typedef {LocalActionUse | RemoteActionUse} ActionUse */

/// The workflow-level `env.FLUTTER_VERSION` and every flutter-action step,
/// each with the raw `flutter-version:` value it carries (null when absent).
///
/// Line-based rather than YAML-parsed on purpose: the guard jobs run `node`
/// against a bare checkout with no `npm ci`, so only the stdlib is available.
/**
 * @param {string} text
 * @returns {{ declared: string | null, steps: VersionedLine[] }}
 */
export function parseWorkflow(text) {
	const lines = text.split('\n');

	// Top-level `env:` keys sit at two spaces. A job-level or step-level env
	// would be indented further, and pinning from one of those would not be
	// visible to the other steps this guard compares.
	const declared = (() => {
		for (let i = 0; i < lines.length; i++) {
			if (!/^env:\s*$/.test(lines[i])) continue;
			for (let j = i + 1; j < lines.length; j++) {
				const line = lines[j];
				if (!line.trim() || line.trimStart().startsWith('#')) continue;
				if (!/^\s/.test(line)) break;
				const m = line.match(/^\s{2}([A-Za-z_][A-Za-z0-9_]*):\s*(.*?)\s*$/);
				if (m && m[1] === ENV_KEY) return unquote(m[2]);
			}
		}
		return null;
	})();

	/** @type {VersionedLine[]} */
	const steps = [];
	for (let i = 0; i < lines.length; i++) {
		const head = lines[i].match(/^(\s*)-\s+uses:\s*\S*subosito\/flutter-action@\S+/);
		if (!head) continue;
		const markerIndent = head[1].length;
		let version = null;
		for (let j = i + 1; j < lines.length; j++) {
			const line = lines[j];
			if (!line.trim() || line.trimStart().startsWith('#')) continue;
			const indent = line.length - line.trimStart().length;
			if (indent <= markerIndent) break;
			const m = line.match(/^\s*flutter-version:\s*(.*?)\s*$/);
			if (m) {
				version = unquote(m[1]);
				break;
			}
		}
		steps.push({ line: i + 1, version });
	}

	return { declared, steps };
}

/** @param {string} value */
function unquote(value) {
	return value.replace(/\s+#.*$/, '').replace(/^["']|["']$/g, '');
}

/// Every `dart pub global activate melos` in a workflow, with the version
/// constraint it passes (null when it passes none and therefore installs
/// whatever is newest). YAML comments are skipped so prose naming the command
/// is not mistaken for an invocation of it.
/**
 * @param {string} text
 * @returns {VersionedLine[]}
 */
export function parseMelosActivations(text) {
	/** @type {VersionedLine[]} */
	const found = [];
	text.split('\n').forEach((line, i) => {
		if (line.trimStart().startsWith('#')) return;
		const m = line.match(/dart\s+pub\s+global\s+activate\s+melos(\s+\S+)?/);
		if (!m) return;
		found.push({ line: i + 1, version: m[1] ? m[1].trim() : null });
	});
	return found;
}

/// A package's resolved version from a pubspec.lock. The lockfile is the
/// source of truth for what the workspace actually resolves, which is the
/// thing `pub global activate` must be told to match.
/**
 * @param {string} lockText
 * @param {string} name
 * @returns {string | null}
 */
export function parseLockedVersion(lockText, name) {
	const lines = lockText.split('\n');
	for (let i = 0; i < lines.length; i++) {
		if (lines[i] !== `  ${name}:`) continue;
		for (let j = i + 1; j < lines.length; j++) {
			// A two-space key starts the next package entry.
			if (/^ {2}\S/.test(lines[j])) break;
			const m = lines[j].match(/^\s+version:\s*(.*?)\s*$/);
			if (m) return unquote(m[1]);
		}
		return null;
	}
	return null;
}

/// Resolve one step's `flutter-version:` to a concrete version string, or
/// explain why it cannot be resolved.
/**
 * @param {{ version: string | null }} step
 * @param {string | null} declared
 * @returns {ResolvedFlutter}
 */
export function resolveVersion(step, declared) {
	if (step.version === null) {
		return {
			error:
				`no \`flutter-version:\` — the step takes only \`channel:\`, so the SDK ` +
				`floats and this job runs whatever Flutter is newest when it starts`,
		};
	}
	const ref = step.version.match(/^\$\{\{\s*env\.([A-Za-z_][A-Za-z0-9_]*)\s*\}\}$/);
	if (ref) {
		if (ref[1] !== ENV_KEY) {
			return { error: `reads \`env.${ref[1]}\`; every pin must read \`env.${ENV_KEY}\`` };
		}
		if (declared === null) {
			return {
				error: `reads \`env.${ENV_KEY}\` but this workflow declares no top-level \`env.${ENV_KEY}\``,
			};
		}
		return { version: declared };
	}
	if (step.version.includes('${{')) {
		return { error: `unrecognised expression \`${step.version}\`; use \`\${{ env.${ENV_KEY} }}\`` };
	}
	return { version: step.version };
}

/** @param {WorkflowFile[]} files */
export function checkFlutter(files) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	/// version -> the `file:line` sites pinning it.
	/** @type {Map<string, string[]>} */
	const versions = new Map();

	for (const { name, text } of files) {
		const { declared, steps } = parseWorkflow(text);
		for (const step of steps) {
			const where = `${name}:${step.line}`;
			const resolved = resolveVersion(step, declared);
			if (resolved.version === undefined) {
				errors.push(`${where} — ${resolved.error}`);
				continue;
			}
			ok.push(`${where} -> ${resolved.version}`);
			const sites = versions.get(resolved.version) ?? [];
			sites.push(where);
			versions.set(resolved.version, sites);
		}
	}

	if (ok.length === 0 && errors.length === 0) {
		errors.push(
			`no \`${ACTION}\` steps found in any workflow. Either every Flutter job ` +
				`was removed, or the action was renamed and this guard now checks nothing.`,
		);
	}

	if (versions.size > 1) {
		const detail = [...versions.entries()]
			.sort((a, b) => a[0].localeCompare(b[0]))
			.map(([version, sites]) => `    ${version} — ${sites.join(', ')}`)
			.join('\n');
		errors.push(
			`workflows pin ${versions.size} different Flutter versions:\n${detail}\n` +
				`  CI is what validates the code the release workflows ship, so a release ` +
				`built on a different SDK than CI tested is an untested binary. Set every ` +
				`workflow's top-level \`env.${ENV_KEY}\` to the same value (decisions.md § 595).`,
		);
	}

	return { errors, ok, versions };
}

/**
 * @param {WorkflowFile[]} files
 * @param {string} lockText
 */
export function checkMelos(files, lockText) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	const locked = parseLockedVersion(lockText, 'melos');

	if (locked === null) {
		return {
			errors: [
				`pubspec.lock has no resolved \`melos\` version. It is a direct dev ` +
					`dependency of the workspace root; if it was removed, drop this check ` +
					`with it rather than leaving it reading nothing.`,
			],
			ok,
			locked,
		};
	}

	let seen = 0;
	for (const { name, text } of files) {
		for (const activation of parseMelosActivations(text)) {
			seen++;
			const where = `${name}:${activation.line}`;
			if (activation.version === null) {
				errors.push(
					`${where} — \`${ACTIVATE}\` passes no version, so it installs whatever ` +
						`melos is newest when the job runs. Pass \`${locked}\` (the version ` +
						`pubspec.lock resolves).`,
				);
				continue;
			}
			if (activation.version !== locked) {
				errors.push(
					`${where} — activates melos ${activation.version}, but pubspec.lock ` +
						`resolves ${locked}. CI would run a different melos than ` +
						`\`dart run melos\` does locally; \`pub global activate\` ignores the ` +
						`workspace, so only this check couples them.`,
				);
				continue;
			}
			ok.push(`${where} -> melos ${activation.version}`);
		}
	}

	if (seen === 0) {
		errors.push(
			`no \`${ACTIVATE}\` lines found in any workflow. Either melos is no longer ` +
				`installed in CI, or the command was reworded and this check now ` +
				`enforces nothing.`,
		);
	}

	return { errors, ok, locked };
}

/// Every `cargo install defmt-print` and every `actions/cache` key naming it,
/// within one span of YAML. A version of null means the install passed no
/// `--version` at all, or the key carried no version.
/**
 * @param {string} text
 * @returns {{ installs: VersionedLine[], cacheKeys: VersionedLine[] }}
 */
export function parseDefmtPrint(text) {
	/** @type {VersionedLine[]} */
	const installs = [];
	/** @type {VersionedLine[]} */
	const cacheKeys = [];
	text.split('\n').forEach((line, i) => {
		if (line.trimStart().startsWith('#')) return;
		if (line.includes(CARGO_INSTALL)) {
			const m = line.match(/--version[= ]\s*['"]?([^'"\s]+)/);
			installs.push({ line: i + 1, version: m ? m[1] : null });
			return;
		}
		// Matched on the cached NAME rather than on a key already shaped the way
		// this check wants: a key simplified to `defmt-print-${{ runner.os }}` is
		// precisely the hazard, and a pattern that only recognised a key carrying
		// a version could not see it.
		const key = line.match(/^\s*key:\s*(\S*defmt-print\S*)/);
		if (key) {
			const version = key[1].match(/defmt-print-(\d+(?:\.\d+)+)/);
			cacheKeys.push({ line: i + 1, version: version ? version[1] : null });
		}
	});
	return { installs, cacheKeys };
}

/// The same, grouped by the JOB whose steps hold them, with file-absolute
/// line numbers.
///
/// A cache key and the install it must agree with are a property of ONE job:
/// the key restores `~/.cargo/bin/defmt-print` for that runner and that
/// runner's `command -v defmt-print ||` then decides whether the pin executes.
/// Reading the whole FILE compared every key against the first install in it,
/// which is right only while every job in the file happens to pin the same
/// version. Two sim jobs pinning different ones — this file has held two sim
/// jobs since the day it was written, and they agree only by hand — made the
/// check wrong in both directions at once: a key correct for its own job was
/// reported stale, and a key that WOULD defeat its own job's pin was reported
/// `[OK]`, which is the exact failure (run 31623789083) the header above
/// records. The step boundaries come from check_ci_diagnostics.mjs, which
/// already parses them and is tested on them.
/**
 * @param {string} text
 * @returns {Map<string, { installs: VersionedLine[], cacheKeys: VersionedLine[] }>}
 */
export function parseDefmtPrintByJob(text) {
	/** @type {Map<string, { installs: VersionedLine[], cacheKeys: VersionedLine[] }>} */
	const byJob = new Map();
	for (const step of parseSteps(text)) {
		const { installs, cacheKeys } = parseDefmtPrint(step.body);
		if (installs.length === 0 && cacheKeys.length === 0) continue;
		const entry = byJob.get(step.job) ?? { installs: [], cacheKeys: [] };
		for (const i of installs) entry.installs.push({ line: step.line + i.line - 1, version: i.version });
		for (const k of cacheKeys) entry.cacheKeys.push({ line: step.line + k.line - 1, version: k.version });
		byJob.set(step.job, entry);
	}
	return byJob;
}

/** @param {WorkflowFile[]} files */
export function checkDefmtPrint(files) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	/** @type {Map<string, string[]>} */
	const versions = new Map();
	let installCount = 0;

	for (const { name, text } of files) {
		for (const [job, { installs, cacheKeys }] of parseDefmtPrintByJob(text)) {
			for (const install of installs) {
				installCount++;
				const where = `${name}:${install.line}`;
				if (install.version === null) {
					errors.push(
						`${where} — \`${CARGO_INSTALL}\` passes no \`--version\`, so it installs ` +
							`whatever defmt-print is newest when the job runs.`,
					);
					continue;
				}
				if (!EXACT_VERSION.test(install.version)) {
					errors.push(
						`${where} — \`--version ${install.version}\` is a range, not a pin; it still ` +
							`admits any release matching it. Pass a bare MAJOR.MINOR.PATCH, which ` +
							`\`cargo install\` reads as an exact version (unlike a Cargo.toml ` +
							`dependency, it is NOT a caret there).`,
					);
					continue;
				}
				ok.push(`${where} -> defmt-print ${install.version}`);
				const sites = versions.get(install.version) ?? [];
				sites.push(where);
				versions.set(install.version, sites);
			}

			// The cache key must carry the version its OWN job installs, or
			// `command -v` keeps the restored binary and the pin never executes.
			// Compared only against an install that is already a valid pin —
			// against a range the comparison means nothing, and reporting it would
			// bury the error worth acting on.
			const installed = installs.find(
				(i) => i.version !== null && EXACT_VERSION.test(i.version),
			)?.version;
			for (const key of cacheKeys) {
				const where = `${name}:${key.line}`;
				if (key.version === null) {
					errors.push(
						`${where} — the defmt-print cache key carries no version, so it cannot ` +
							`move when the pin does. The install is \`command -v defmt-print || cargo ` +
							`install ...\`, so this key keeps restoring whatever binary was cached ` +
							`under it and the pin never runs. Put the pinned version in the key.`,
					);
					continue;
				}
				if (installed === undefined) {
					// An install that exists but is not a valid pin has already been
					// reported; comparing a key against a range means nothing, and a
					// second line here would bury the error worth acting on. A job that
					// caches the binary and never installs it is a different thing:
					// nothing in it states which binary the key may hold.
					if (installs.length === 0) {
						errors.push(
							`${where} — job \`${job}\` restores a defmt-print cache but never runs ` +
								`\`${CARGO_INSTALL}\`, so nothing in the job says which binary the key ` +
								`is allowed to hold. Install it here too, or drop the cache step.`,
						);
					}
					continue;
				}
				if (key.version !== installed) {
					errors.push(
						`${where} — cache key names defmt-print ${key.version} but job \`${job}\` ` +
							`installs ${installed}. The install is \`command -v defmt-print || cargo ` +
							`install ...\`, so this key would restore the old binary and the pin ` +
							`would never run. Put the pinned version in the key.`,
					);
					continue;
				}
				ok.push(`${where} -> cache key matches job \`${job}\`'s defmt-print ${installed}`);
			}
		}
	}

	if (installCount === 0) {
		errors.push(
			`no \`${CARGO_INSTALL}\` lines found in any workflow job. Either the firmware sim ` +
				`no longer decodes defmt, or the command was reworded and this check now ` +
				`enforces nothing.`,
		);
	}

	if (versions.size > 1) {
		const detail = [...versions.entries()]
			.sort((a, b) => a[0].localeCompare(b[0]))
			.map(([version, sites]) => `    ${version} — ${sites.join(', ')}`)
			.join('\n');
		errors.push(`the firmware-sim jobs install ${versions.size} different defmt-print versions:\n${detail}`);
	}

	return { errors, ok, versions };
}

/// Every `uses:` line in a workflow or composite action, commented or not, as
/// `{ line, ref, comment, commented }`. A line whose value is not shaped like
/// an action reference is prose mentioning the key, not a use of it.
/**
 * @param {string} text
 * @returns {ActionUse[]}
 */
export function parseActionUses(text) {
	/** @type {ActionUse[]} */
	const found = [];
	text.split('\n').forEach((line, i) => {
		const m = line.match(ACTION_USES);
		if (!m) return;
		const ref = unquote(m[1]);
		const commented = line.trimStart().startsWith('#');
		const comment = m[2] ?? null;
		if (ref.startsWith('./') || ref.startsWith('../')) {
			found.push({ line: i + 1, ref, comment, commented, local: true });
			return;
		}
		const parts = ref.match(ACTION_REF);
		if (!parts) return;
		found.push({ line: i + 1, ref, comment, commented, local: false, action: parts[1], gitRef: parts[2] });
	});
	return found;
}

/** @param {WorkflowFile[]} files */
export function checkActionPins(files) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	let seen = 0;

	for (const { name, text } of files) {
		for (const use of parseActionUses(text)) {
			if (use.local) continue;
			seen++;
			const where = `${name}:${use.line}`;
			const { action, gitRef } = use;
			const dead = use.commented ? ' (commented out — which is how this one drifted, not a reason to skip it)' : '';
			if (!COMMIT_SHA.test(gitRef)) {
				errors.push(
					`${where} — \`${action}@${gitRef}\` pins a tag, not a commit${dead}. A tag is ` +
						`mutable: the publisher can move it onto anything, and it then runs with ` +
						`this repo's GITHUB_TOKEN. Resolve the SHA with \`git ls-remote ` +
						`https://github.com/${action.split('/').slice(0, 2).join('/')}.git ` +
						`refs/tags/${gitRef}\` (dereference an annotated tag to its commit) and ` +
						`record the version in a trailing \`# ${gitRef}\` comment.`,
				);
				continue;
			}
			if (!use.comment || !/^v?\d/.test(use.comment)) {
				errors.push(
					`${where} — \`${action}\` is SHA-pinned but carries no trailing \`# vN\` ` +
						`comment${dead}, so nothing on the line says which release it is and an ` +
						`upgrade cannot be reviewed. Append the version the SHA came from.`,
				);
				continue;
			}
			ok.push(`${where} -> ${action} @ ${gitRef.slice(0, 7)} (${use.comment})`);
		}
	}

	if (seen === 0) {
		errors.push(
			`no third-party \`uses:\` lines found in any workflow. Either every action ` +
				`was removed, or the parser stopped matching and this check now enforces ` +
				`nothing.`,
		);
	}

	return { errors, ok, seen };
}

/**
 * @param {WorkflowFile[]} files
 * @param {string} lockText
 * @param {WorkflowFile[]} [compositeFiles]
 */
export function checkAll(files, lockText, compositeFiles = []) {
	const flutter = checkFlutter(files);
	const melos = checkMelos(files, lockText);
	const defmt = checkDefmtPrint(files);
	const actions = checkActionPins([...files, ...compositeFiles]);
	return {
		errors: [...flutter.errors, ...melos.errors, ...defmt.errors, ...actions.errors],
		ok: [...flutter.ok, ...melos.ok, ...defmt.ok, ...actions.ok],
		flutter,
		melos,
		defmt,
		actions,
	};
}

/** @param {string} dir */
function readWorkflows(dir) {
	return readdirSync(dir)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.sort()
		.map((name) => ({ name, text: readFileSync(join(dir, name), 'utf-8') }));
}

/** @param {string} dir */
export function readCompositeActions(dir) {
	return readdirSync(dir, { withFileTypes: true })
		.filter((e) => e.isDirectory())
		.map((e) => e.name)
		.sort()
		.flatMap((name) =>
			['action.yml', 'action.yaml']
				.map((f) => join(dir, name, f))
				.filter((f) => existsSync(f))
				.map((f) => ({ name: `actions/${name}/${basename(f)}`, text: readFileSync(f, 'utf-8') })),
		);
}

function main() {
	const { errors, ok, flutter, melos, defmt, actions } = checkAll(
		readWorkflows(WORKFLOW_DIR),
		readFileSync(LOCKFILE, 'utf-8'),
		readCompositeActions(ACTION_DIR),
	);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);

	if (errors.length > 0) {
		console.error(`\n${errors.length} toolchain pin problem(s).`);
		return 1;
	}
	console.log(
		`\n${flutter.ok.length} flutter-action step(s) pin Flutter ` +
			`${[...flutter.versions.keys()][0]}; ${melos.ok.length} activation(s) pin ` +
			`melos ${melos.locked}, matching pubspec.lock; defmt-print pinned to ` +
			`${[...defmt.versions.keys()][0]} with matching cache keys; ` +
			`${actions.ok.length} third-party action reference(s) pinned by commit SHA.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
