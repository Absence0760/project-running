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
//   Node — every `actions/setup-node` step names a `node-version`, and all of
//     them agree. Same shape as Flutter and for the same reason: no in-repo
//     file resolves the runtime, so the workflows ARE the source of truth, and
//     a release built on a Node that CI never ran is an untested binary. A step
//     with no `node-version` at all is the `channel: stable` shape one more
//     time — it takes whatever the runner image ships that week.
//
//   The developer toolchain — `.tool-versions`, the file a contributor points
//     `asdf install` / `mise install` at. Every line in it, ACTIVE OR
//     COMMENTED, is compared against the pin the repo enforces for that
//     toolchain, because a commented pin is a claim the next reader will
//     uncomment (the § 711 reasoning about a commented action pin). Nothing
//     read this file, and it pinned `nodejs 22` while all 21 setup-node steps
//     ran 24 (decisions § 911).
//
//   Rust (firmware) — `apps/custom_watch/rust-toolchain.toml` names an EXACT
//     `MAJOR.MINOR.PATCH` channel, never `stable`/`beta`/`nightly` and never a
//     two-component `1.98`. The firmware job runs clippy with `-D warnings`
//     across three feature sets, and a zero-warning bar on a floating channel
//     hands the toolchain vendor the power to break the build on whoever
//     pushes next: clippy 1.98 added `chunks_exact_to_as_chunks` and failed CI
//     on two call sites untouched for weeks, from a PR changing docs
//     (decisions.md § 705). Same rule, same reason, as the Flutter pin — and
//     it was the one toolchain in this repo that nothing checked.
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
// One file resolves the firmware's Rust channel, and every firmware job
// installs from it (`rustup show` honours it automatically).
export const RUST_TOOLCHAIN = join(REPO_ROOT, 'apps', 'custom_watch', 'rust-toolchain.toml');
export const TOOL_VERSIONS = join(REPO_ROOT, '.tool-versions');
export const GO_MODS = ['apps/job_worker/go.mod', 'apps/graph_cycle/go.mod'];
export const TERRAFORM_WORKFLOW = 'terraform.yml';

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
/// A step that `uses:` one particular action, and the version key inside it.
///
/// The `uses:` is found wherever it sits: a step written `- uses: x` carries it
/// on the marker line, and a step written `- name: …` then `uses: x` carries it
/// one line down. Reading only the first form is not hypothetical — it is how
/// this file's Node rail first shipped, and `audit.yml`'s setup-node step is
/// written the second way, so the one workflow whose comment CLAIMS it "matches
/// the rest of the workflows in this repo" was the one the guard could not see.
/// 54 steps across the committed workflows use that form.
/**
 * @param {string} text
 * @param {RegExp} usesRe with the indent as group 1 and the `- ` marker as group 2
 * @param {string} versionKey
 * @returns {VersionedLine[]}
 */
export function parseUsesStepVersions(text, usesRe, versionKey) {
	const lines = text.split('\n');
	const keyRe = new RegExp(`^\\s*${versionKey}:\\s*(.*?)\\s*$`);
	/** @type {VersionedLine[]} */
	const steps = [];

	for (let i = 0; i < lines.length; i++) {
		if (lines[i].trimStart().startsWith('#')) continue;
		const m = lines[i].match(usesRe);
		if (!m) continue;

		let start = i;
		let markerIndent = m[1].length;
		if (!m[2]) {
			// Walk back to the step's own `- ` marker, past the sibling keys of
			// this step (`with:`, `env:` and their children), which are all at or
			// deeper than the `uses:` line.
			start = -1;
			for (let j = i - 1; j >= 0; j--) {
				const line = lines[j];
				if (!line.trim() || line.trimStart().startsWith('#')) continue;
				if (line.length - line.trimStart().length >= m[1].length) continue;
				const dash = line.match(/^(\s*)-\s/);
				if (dash) {
					start = j;
					markerIndent = dash[1].length;
				}
				break;
			}
			// A `uses:` under no list marker is not a step; reporting it would
			// invent a site.
			if (start === -1) continue;
		}

		/** @type {string | null} */
		let version = null;
		for (let j = start + 1; j < lines.length; j++) {
			const line = lines[j];
			if (!line.trim() || line.trimStart().startsWith('#')) continue;
			if (line.length - line.trimStart().length <= markerIndent) break;
			const v = line.match(keyRe);
			if (v) {
				version = unquote(v[1]);
				break;
			}
		}
		steps.push({ line: start + 1, version });
	}

	return steps;
}

export const FLUTTER_USES = /^(\s*)(-\s+)?uses:\s*\S*subosito\/flutter-action@\S+/;
export const SETUP_NODE_USES = /^(\s*)(-\s+)?uses:\s*\S*actions\/setup-node@\S+/;

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

	return { declared, steps: parseUsesStepVersions(text, FLUTTER_USES, 'flutter-version') };
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

/// The `channel` a rust-toolchain.toml declares, or null when the file names
/// none. TOML, not YAML, and read line-wise for the same stdlib-only reason
/// everything else here is.
/**
 * @param {string} text
 * @returns {string | null}
 */
export function parseRustChannel(text) {
	for (const line of text.split('\n')) {
		const bare = line.replace(/#.*$/, '');
		const m = bare.match(/^\s*channel\s*=\s*(.*?)\s*$/);
		if (m) return unquote(m[1]);
	}
	return null;
}

/// `apps/custom_watch/rust-toolchain.toml` must pin an exact version.
///
/// A missing file, or a file naming no channel, is an error rather than a
/// silent pass: rustup would then fall back to the host default and the
/// firmware would build on whatever that machine happens to carry, which is
/// the floating channel this check exists to refuse.
/**
 * @param {string | null} text null when the file is absent
 * @returns {{ errors: string[], ok: string[], channel: string | null }}
 */
export function checkRustToolchain(text) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	if (text === null) {
		errors.push(
			`apps/custom_watch/rust-toolchain.toml is missing. Three firmware jobs run ` +
				`\`rustup show\` inside apps/custom_watch and take their toolchain from it; ` +
				`without the file each runner installs its own default and clippy ` +
				`\`-D warnings\` breaks on whoever pushes next (decisions.md § 705).`,
		);
		return { errors, ok, channel: null };
	}
	const channel = parseRustChannel(text);
	if (channel === null) {
		errors.push(
			`apps/custom_watch/rust-toolchain.toml declares no \`channel\`, so rustup ` +
				`resolves the host default and the firmware's Rust version floats ` +
				`(decisions.md § 705).`,
		);
		return { errors, ok, channel };
	}
	if (!EXACT_VERSION.test(channel)) {
		errors.push(
			`apps/custom_watch/rust-toolchain.toml pins \`channel = "${channel}"\`, which is ` +
				`not an exact MAJOR.MINOR.PATCH version. The firmware job runs clippy with ` +
				`\`-D warnings\` across three feature sets, so a floating channel means the ` +
				`toolchain vendor decides when the build breaks and it breaks on whoever ` +
				`pushes next, not on whoever chose to upgrade — clippy 1.98 failed CI on two ` +
				`call sites untouched for weeks, from a PR changing docs (decisions.md § 705). ` +
				`Bumping it is a deliberate commit that carries its own fallout.`,
		);
		return { errors, ok, channel };
	}
	ok.push(`apps/custom_watch/rust-toolchain.toml -> rust ${channel}`);
	return { errors, ok, channel };
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
 * @param {string | null} [rustToolchainText]
 */
/// Every `actions/setup-node` step, with the `node-version:` it carries (null
/// when it carries none and therefore takes the runner image's default).
/// Shaped exactly like `parseWorkflow`'s Flutter steps and for the same
/// reason — a step's version is read from the step's own block, not from
/// anywhere else in the file that happens to say a number.
/**
 * @param {string} text
 * @returns {VersionedLine[]}
 */
export function parseNodeSteps(text) {
	return parseUsesStepVersions(text, SETUP_NODE_USES, 'node-version');
}

/// Rule: every setup-node step names a version, and every one names the same.
/**
 * @param {WorkflowFile[]} files
 * @returns {{ errors: string[], ok: string[], versions: Map<string, string[]> }}
 */
export function checkNode(files) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	/** @type {Map<string, string[]>} */
	const versions = new Map();

	for (const { name, text } of files) {
		for (const step of parseNodeSteps(text)) {
			const where = `${name}:${step.line}`;
			if (step.version === null) {
				errors.push(
					`${where} — this \`actions/setup-node\` step names no \`node-version\`, so ` +
						`it installs whatever the runner image ships that week. That is the ` +
						`\`channel: stable\` shape § 595 was about: the runtime moves under code ` +
						`nobody touched, and the blame lands on whichever PR ran next.`,
				);
				continue;
			}
			ok.push(`${where} -> node ${step.version}`);
			const sites = versions.get(step.version) ?? [];
			sites.push(where);
			versions.set(step.version, sites);
		}
	}

	if (ok.length === 0 && errors.length === 0) {
		errors.push(
			`no \`actions/setup-node\` steps found in any workflow. Either every Node job ` +
				`was removed, or the action was renamed and this rule now checks nothing.`,
		);
	}

	if (versions.size > 1) {
		const detail = [...versions.entries()]
			.sort((a, b) => a[0].localeCompare(b[0]))
			.map(([version, sites]) => `    ${version} — ${sites.join(', ')}`)
			.join('\n');
		errors.push(
			`workflows pin ${versions.size} different Node versions:\n${detail}\n` +
				`  CI is what validates the code the release workflows ship, so a release ` +
				`built on a runtime CI never ran is an untested binary — the same argument ` +
				`§ 595 makes for the Flutter SDK.`,
		);
	}

	return { errors, ok, versions };
}

/// Every `<plugin> <version>` line of `.tool-versions`, commented or not.
/// A commented line is kept rather than skipped: uncommenting it is one
/// keystroke and the version it then installs is the claim being checked.
/**
 * @param {string} text
 * @returns {Map<string, { line: number, version: string, commented: boolean }>}
 */
export function parseToolVersions(text) {
	/** @type {Map<string, { line: number, version: string, commented: boolean }>} */
	const out = new Map();
	text.split('\n').forEach((raw, i) => {
		const m = raw.match(/^(#\s*)?([a-z][a-z0-9_-]*)\s+(\S+)\s*$/);
		if (!m) return;
		if (out.has(m[2])) return;
		out.set(m[2], { line: i + 1, version: m[3], commented: m[1] !== undefined });
	});
	return out;
}

/// The pins the repo itself enforces, as `plugin -> { version, source }`.
/// Only these can be checked; a plugin the repo does not pin is reported as
/// unbacked rather than compared against nothing.
/**
 * @param {{ flutter?: string | null, rust?: string | null, node?: string | null, go?: string | null, terraform?: string | null }} pins
 * @returns {Map<string, { version: string, source: string }>}
 */
export function repoPins(pins) {
	/** @type {Map<string, { version: string, source: string }>} */
	const out = new Map();
	if (pins.node) out.set('nodejs', { version: pins.node, source: "each workflow's `actions/setup-node` step" });
	if (pins.rust) out.set('rust', { version: pins.rust, source: 'apps/custom_watch/rust-toolchain.toml' });
	if (pins.go) out.set('golang', { version: pins.go, source: GO_MODS.join(' + ') });
	if (pins.flutter) out.set('flutter', { version: pins.flutter, source: "each workflow's top-level env.FLUTTER_VERSION" });
	if (pins.terraform) out.set('terraform', { version: pins.terraform, source: `.github/workflows/${TERRAFORM_WORKFLOW}` });
	return out;
}

/// `nodejs` is compared on the MAJOR alone: asdf needs a version it can
/// resolve to a build, CI states a major, and demanding they match to the
/// patch would make every runner-image bump a repo edit. Every other pin is
/// exact, because both sides already state one.
/** @param {string} plugin @param {string} declared @param {string} pinned */
export function toolVersionAgrees(plugin, declared, pinned) {
	if (plugin === 'nodejs') return declared.split('.')[0] === pinned.split('.')[0];
	return declared === pinned;
}

/**
 * @param {string | null} toolVersionsText
 * @param {Map<string, { version: string, source: string }>} pins
 * @returns {{ errors: string[], ok: string[], unbacked: string[] }}
 */
export function checkToolVersions(toolVersionsText, pins) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	/** @type {string[]} */
	const unbacked = [];

	if (toolVersionsText === null) {
		errors.push(
			`.tool-versions is missing. It is what a contributor points \`asdf install\` / ` +
				`\`mise install\` at, so without it the developer toolchain is whatever each ` +
				`machine happens to have.`,
		);
		return { errors, ok, unbacked };
	}

	const declared = parseToolVersions(toolVersionsText);
	for (const [plugin, { version, source }] of pins) {
		const entry = declared.get(plugin);
		if (!entry) {
			errors.push(
				`.tool-versions names no \`${plugin}\` line, but this repo pins ${plugin} to ` +
					`${version} in ${source}. A contributor installing from that file gets ` +
					`whatever their machine has for a toolchain CI holds to an exact version.`,
			);
			continue;
		}
		if (!toolVersionAgrees(plugin, entry.version, version)) {
			errors.push(
				`.tool-versions:${entry.line} — ${entry.commented ? 'the commented ' : ''}` +
					`\`${plugin} ${entry.version}\` disagrees with the ${version} this repo pins ` +
					`in ${source}. ${entry.commented
						? 'A commented pin is not dead: uncommenting it is one keystroke, and it ' +
							'then installs the wrong version silently.'
						: 'A contributor who installs from this file develops on a toolchain CI ' +
							'never runs.'}`,
			);
			continue;
		}
		ok.push(`.tool-versions:${entry.line} -> ${plugin} ${entry.version} matches ${source}`);
	}

	for (const [plugin, entry] of declared) {
		if (pins.has(plugin)) continue;
		unbacked.push(
			`.tool-versions:${entry.line} — \`${plugin} ${entry.version}\` has no in-repo pin ` +
				`to check it against`,
		);
	}

	return { errors, ok, unbacked };
}

/// The `go` directive of every module, which must agree with itself before it
/// can be a pin.
/**
 * @param {readonly {path: string, text: string}[]} mods
 * @returns {{ version: string | null, errors: string[] }}
 */
export function parseGoDirective(mods) {
	/** @type {string[]} */
	const errors = [];
	/** @type {Map<string, string[]>} */
	const seen = new Map();
	for (const { path, text } of mods) {
		const m = text.split('\n').find((l) => /^go\s+\d/.test(l));
		if (!m) {
			errors.push(`${path} declares no \`go\` directive`);
			continue;
		}
		const v = m.replace(/^go\s+/, '').trim();
		seen.set(v, [...(seen.get(v) ?? []), path]);
	}
	if (seen.size > 1) {
		errors.push(
			`the Go modules declare ${seen.size} different \`go\` directives: ` +
				`${[...seen.entries()].map(([v, p]) => `${v} (${p.join(', ')})`).join('; ')}`,
		);
		return { version: null, errors };
	}
	return { version: [...seen.keys()][0] ?? null, errors };
}

/** @param {string} text */
export function parseTerraformVersion(text) {
	const m = text.split('\n').find((l) => /^\s*terraform_version:/.test(l));
	return m ? unquote(m.replace(/^\s*terraform_version:\s*/, '')) : null;
}

/**
 * @param {WorkflowFile[]} files
 * @param {string} lockText
 * @param {WorkflowFile[]} [compositeFiles]
 * @param {string | null} [rustToolchainText]
 * @param {string | null} [toolVersionsText]
 * @param {readonly {path: string, text: string}[]} [goMods]
 */
export function checkAll(
	files,
	lockText,
	compositeFiles = [],
	rustToolchainText = null,
	toolVersionsText = null,
	goMods = [],
) {
	const flutter = checkFlutter(files);
	const melos = checkMelos(files, lockText);
	const defmt = checkDefmtPrint(files);
	const actions = checkActionPins([...files, ...compositeFiles]);
	const rust = checkRustToolchain(rustToolchainText);
	const node = checkNode(files);
	const go = parseGoDirective(goMods);
	const terraform = (() => {
		const f = files.find((x) => x.name === TERRAFORM_WORKFLOW);
		return f ? parseTerraformVersion(f.text) : null;
	})();
	const tools = checkToolVersions(
		toolVersionsText,
		repoPins({
			node: node.versions.size === 1 ? [...node.versions.keys()][0] : null,
			rust: rust.channel ?? null,
			go: go.version,
			flutter: flutter.versions.size === 1 ? [...flutter.versions.keys()][0] : null,
			terraform,
		}),
	);
	return {
		errors: [
			...flutter.errors,
			...melos.errors,
			...defmt.errors,
			...actions.errors,
			...rust.errors,
			...node.errors,
			...go.errors,
			...tools.errors,
		],
		ok: [...flutter.ok, ...melos.ok, ...defmt.ok, ...actions.ok, ...rust.ok, ...node.ok, ...tools.ok],
		flutter,
		melos,
		defmt,
		actions,
		rust,
		node,
		tools,
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
	const { errors, ok, flutter, melos, defmt, actions, rust, node, tools } = checkAll(
		readWorkflows(WORKFLOW_DIR),
		readFileSync(LOCKFILE, 'utf-8'),
		readCompositeActions(ACTION_DIR),
		existsSync(RUST_TOOLCHAIN) ? readFileSync(RUST_TOOLCHAIN, 'utf-8') : null,
		existsSync(TOOL_VERSIONS) ? readFileSync(TOOL_VERSIONS, 'utf-8') : null,
		GO_MODS.filter((m) => existsSync(join(REPO_ROOT, m))).map((path) => ({
			path,
			text: readFileSync(join(REPO_ROOT, path), 'utf-8'),
		})),
	);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of tools.unbacked) console.log(`[SKIP] ${line}`);
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
			`${actions.ok.length} third-party action reference(s) pinned by commit SHA; ` +
			`the firmware's Rust channel pinned to ${rust.channel}; ` +
			`${node.ok.length} setup-node step(s) on Node ${[...node.versions.keys()][0]}; ` +
			`${tools.ok.length} of .tool-versions' line(s) match the pin this repo enforces, ` +
			`with ${tools.unbacked.length} carrying no in-repo pin to check.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
