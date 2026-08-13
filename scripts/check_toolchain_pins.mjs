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
// The vacuous-pass case is checked for both: if the action is renamed, or the
// activate line reworded, this fails rather than reporting success over an
// empty set. A guard that inspects nothing enforces nothing.
//
// Run: `node scripts/check_toolchain_pins.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_toolchain_pins.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WORKFLOW_DIR = join(REPO_ROOT, '.github', 'workflows');
export const LOCKFILE = join(REPO_ROOT, 'pubspec.lock');

const ACTION = 'subosito/flutter-action@';
const ENV_KEY = 'FLUTTER_VERSION';
const ACTIVATE = 'dart pub global activate melos';

/// The workflow-level `env.FLUTTER_VERSION` and every flutter-action step,
/// each with the raw `flutter-version:` value it carries (null when absent).
///
/// Line-based rather than YAML-parsed on purpose: the guard jobs run `node`
/// against a bare checkout with no `npm ci`, so only the stdlib is available.
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

function unquote(value) {
	return value.replace(/\s+#.*$/, '').replace(/^["']|["']$/g, '');
}

/// Every `dart pub global activate melos` in a workflow, with the version
/// constraint it passes (null when it passes none and therefore installs
/// whatever is newest). YAML comments are skipped so prose naming the command
/// is not mistaken for an invocation of it.
export function parseMelosActivations(text) {
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

export function checkFlutter(files) {
	const errors = [];
	const ok = [];
	/// version -> the `file:line` sites pinning it.
	const versions = new Map();

	for (const { name, text } of files) {
		const { declared, steps } = parseWorkflow(text);
		for (const step of steps) {
			const where = `${name}:${step.line}`;
			const resolved = resolveVersion(step, declared);
			if (resolved.error) {
				errors.push(`${where} — ${resolved.error}`);
				continue;
			}
			ok.push(`${where} -> ${resolved.version}`);
			if (!versions.has(resolved.version)) versions.set(resolved.version, []);
			versions.get(resolved.version).push(where);
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

export function checkMelos(files, lockText) {
	const errors = [];
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

export function checkAll(files, lockText) {
	const flutter = checkFlutter(files);
	const melos = checkMelos(files, lockText);
	return {
		errors: [...flutter.errors, ...melos.errors],
		ok: [...flutter.ok, ...melos.ok],
		flutter,
		melos,
	};
}

function readWorkflows(dir) {
	return readdirSync(dir)
		.filter((f) => f.endsWith('.yml') || f.endsWith('.yaml'))
		.sort()
		.map((name) => ({ name, text: readFileSync(join(dir, name), 'utf-8') }));
}

function main() {
	const { errors, ok, flutter, melos } = checkAll(
		readWorkflows(WORKFLOW_DIR),
		readFileSync(LOCKFILE, 'utf-8'),
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
			`melos ${melos.locked}, matching pubspec.lock.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
