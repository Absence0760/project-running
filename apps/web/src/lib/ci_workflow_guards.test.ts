// The shape of the repo's own automation, guarded here because each of
// these fails GREEN: a workflow that runs nothing, a gate that waits on
// nothing, and an agent the loader silently drops all report success.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('release-web.yml runs the production-env guard before npm run build', () => {
	// Reason: the guard exists to fail loud on a missing PUBLIC_* secret
	// rather than ship a static artifact whose share / og pages all
	// resolve to empty. The workflow MUST invoke
	// `apps/web/scripts/check_production_env.mjs` ahead of the build
	// step, and it MUST thread every secret the helper enforces
	// (SUPABASE_URL, SUPABASE_ANON_KEY, MAPTILER_KEY,
	// REVENUECAT_WEB_API_KEY) into the step's env block — otherwise the
	// helper sees empty strings and fails the release on every tag.
	const wf = read('../../.github/workflows/release-web.yml');
	const guardIdx = wf.indexOf('check_production_env.mjs');
	const buildIdx = wf.indexOf('npm run build --workspace=apps/web');
	assert.ok(guardIdx >= 0, 'release-web.yml must invoke check_production_env.mjs.');
	assert.ok(buildIdx >= 0, 'release-web.yml must run `npm run build --workspace=apps/web`.');
	assert.ok(
		guardIdx < buildIdx,
		'release-web.yml must invoke check_production_env.mjs BEFORE `npm run build` — failing after build defeats the guard.',
	);
	// Locate the guard step's env block. Match from the `node` line
	// backward to the nearest `env:` keyword.
	const guardStep = wf.match(
		/env:\s*\n([\s\S]*?)\n\s*run:\s*node apps\/web\/scripts\/check_production_env\.mjs/,
	);
	assert.ok(
		guardStep,
		'Could not locate the env: block immediately preceding `node apps/web/scripts/check_production_env.mjs` in release-web.yml.',
	);
	const env = guardStep![1];
	for (const key of [
		'PUBLIC_SUPABASE_URL',
		'PUBLIC_SUPABASE_ANON_KEY',
		'PUBLIC_MAPTILER_KEY',
		'PUBLIC_REVENUECAT_WEB_CHECKOUT_URL',
		// Pro perk flags: the guard requires the RevenueCat checkout URL
		// only when one of these is truthy, so they must reach the guard's
		// env or a sellable Pro would pass with no checkout link.
		'PUBLIC_COACH_ENABLED',
		'PUBLIC_ROUTE_GEN_ENABLED',
	]) {
		assert.match(
			env,
			new RegExp(`${key}:\\s*\\$\\{\\{\\s*secrets\\.${key}\\s*\\}\\}`),
			`release-web.yml guard step must pass ${key} from the repo secret. Adding a new required key to check_production_env.mjs without wiring the secret here fails the release on every tag.`,
		);
	}
});

test('no PR-triggered workflow is scoped to a base branch, so a stacked PR is still gated', () => {
	const dir = resolve(__dirname, '../../../..', '.github/workflows');
	const exempt = new Set(['dependabot-auto-merge.yml']);
	const offenders: string[] = [];
	let checked = 0;

	for (const name of readdirSync(dir)) {
		if (!/\.ya?ml$/.test(name) || exempt.has(name)) continue;
		const src = readFileSync(resolve(dir, name), 'utf-8');
		// The `on:` block only, so a `branches:` key inside a job step
		// (a checkout ref, say) cannot be mistaken for a trigger filter.
		const on = /^on:\n((?:[ \t].*\n|\n)*)/m.exec(src)?.[1];
		if (!on) continue;
		const pr = /^ {2}pull_request(_target)?:\n((?: {4}.*\n|\n)*)/m.exec(on);
		if (!pr) continue;
		checked++;
		if (/^ {4}branches:/m.test(pr[2])) offenders.push(name);
	}

	assert.ok(checked >= 5, `expected several PR-triggered workflows, found ${checked}`);
	assert.deepEqual(
		offenders,
		[],
		`these workflows filter their pull_request trigger to a base branch, so a PR ` +
			`stacked on another feature branch skips them entirely: ${offenders.join(', ')}. ` +
			`Remove the \`branches:\` key under \`pull_request:\` (keep it under \`push:\`), ` +
			`or add the file to the exempt set with a comment saying why.`,
	);
});

// The required status check on `main` is a job named `CI gate`, and it was
// once emitted by TWO workflows: ci.yml's real ~19-job aggregator and a
// `ci-gate-docs.yml` that passed trivially in ~2 s, because ci.yml used to
// skip itself on docs-only diffs via `paths-ignore` and would otherwise
// leave the context pending forever. GitHub does not require every check
// sharing a name to pass: on #457 (backend SQL + decisions.md) the PR read
// `mergeStateStatus = UNSTABLE` — mergeable — with `CI gate = success` from
// the trivial emitter while 40 real checks were still queued, so unverified
// code could merge. #577 deleted that workflow and made ci.yml always run,
// with its heavy jobs skipping on a docs-only diff instead.
//
// This pins the single-emitter half, which nothing else does. The failure is
// invisible from the PR page — a second emitter shows up as a green check
// with the expected name — and the file has been proposed again since (a
// templates-repo sync), written to satisfy the base-branch guard above, so
// passing CI is not evidence that a re-add is safe.

test('exactly one workflow emits the required `CI gate` check', () => {
	const dir = resolve(__dirname, '../../../..', '.github/workflows');
	const emitters: string[] = [];

	for (const name of readdirSync(dir)) {
		if (!/\.ya?ml$/.test(name)) continue;
		const src = readFileSync(resolve(dir, name), 'utf-8');
		// A job's `name:` is what GitHub publishes as the check's name. Match it
		// indented (a job key), never at column 0, which is the workflow's own
		// name — "CI gate (docs)" as a workflow title is harmless, a job named
		// "CI gate" inside it is not.
		if (/^[ \t]+name:[ \t]*['"]?CI gate['"]?[ \t]*$/m.test(src)) emitters.push(name);
	}

	assert.deepEqual(
		emitters,
		['ci.yml'],
		`the required \`CI gate\` check must be emitted by ci.yml alone, but these ` +
			`workflows declare a job named "CI gate": ${emitters.join(', ')}. A second ` +
			`emitter can satisfy branch protection while ci.yml's real jobs are still ` +
			`queued (observed on #457, fixed by #577) — so a docs-touching PR merges ` +
			`unverified. If ci.yml ever needs to skip itself again, make the gate job ` +
			`report from ci.yml regardless and let the heavy jobs skip instead.`,
	);
});

// Claude resolves a subagent by the `name:` in its frontmatter, not by path,
// so two files declaring one name are two definitions of the same agent and
// which one answers is not something a reader can predict. A templates-repo
// sync proposed `.claude/agents/repo-security-auditor.md` and
// `.claude/agents/compliance-auditor.md` while this repo already carried both
// under `.claude/agents/auditors/` — additive by path, colliding by name, and
// the incoming pair described a different application's architecture (a CMS
// webhook, a DynamoDB orders store) while dropping the `Write` tool the
// `/audit/*` commands need to persist findings to `reviews/`. A wrong-but-
// plausible auditor is worse than a missing one: it reports confidently
// against paths this repo does not have.

test('every .claude agent declares a unique name', () => {
	const root = resolve(__dirname, '../../../..', '.claude/agents');
	const byName = new Map<string, string[]>();

	const walk = (dir: string, rel: string) => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const next = resolve(dir, entry.name);
			if (entry.isDirectory()) {
				walk(next, `${rel}${entry.name}/`);
				continue;
			}
			if (!entry.name.endsWith('.md')) continue;
			const front = /^---\n([\s\S]*?)\n---/.exec(readFileSync(next, 'utf-8'))?.[1];
			const name = front && /^name:[ \t]*(.+?)[ \t]*$/m.exec(front)?.[1];
			if (!name) continue;
			byName.set(name, [...(byName.get(name) ?? []), `${rel}${entry.name}`]);
		}
	};
	walk(root, '');

	const duplicates = [...byName.entries()]
		.filter(([, files]) => files.length > 1)
		.map(([name, files]) => `${name} (${files.join(', ')})`);

	assert.ok(byName.size >= 20, `expected the agent fleet, found ${byName.size} named agents`);
	assert.deepEqual(
		duplicates,
		[],
		`these agent names are declared by more than one file, so which definition ` +
			`answers is unpredictable: ${duplicates.join('; ')}. Delete the duplicate or ` +
			`rename one — a path difference does not separate them.`,
	);
});
