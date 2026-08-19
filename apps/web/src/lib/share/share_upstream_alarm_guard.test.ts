import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(dir, '../../../../..');
const alarms = readFileSync(resolve(repoRoot, 'infra/modules/web-stack/alarms.tf'), 'utf8');

/// A share lookup that swallows Supabase's `error` degrades an outage into a
/// clean 404: the Lambda returns a handled response, so the AWS `Errors`
/// metric never moves and nothing pages. `share_session_lookup` and
/// `share_workout_lookup` shipped that way. These two checks make the failure
/// mode detectable instead of relying on each new lookup remembering.

const lookupFiles = readdirSync(dir).filter(
	(f) => f.startsWith('share_') && f.endsWith('_lookup.ts'),
);

test('every share lookup inspects the Supabase error and tags it', () => {
	assert.ok(lookupFiles.length >= 8, 'expected the share lookups to be here');
	for (const f of lookupFiles) {
		const src = readFileSync(resolve(dir, f), 'utf8');
		assert.match(
			src,
			/if \(error\) \{/,
			`${f} never inspects the Supabase \`error\`, so an outage renders as a clean ` +
				'not-found with no Lambda Errors metric and nobody is paged',
		);
		assert.match(
			src,
			/console\.error\(\s*'\[share-[a-z]+\] upstream_unreachable'/,
			`${f} must emit the tagged \`[share-<surface>] upstream_unreachable\` line the ` +
				'CloudWatch metric filter keys off',
		);
	}
});

test('every emitted upstream tag has a metric filter in alarms.tf', () => {
	const surfaces = new Set<string>();
	for (const f of lookupFiles) {
		const src = readFileSync(resolve(dir, f), 'utf8');
		for (const m of src.matchAll(/'\[share-([a-z]+)\] upstream_unreachable'/g)) {
			surfaces.add(m[1]);
		}
	}
	assert.ok(surfaces.size >= 8, `expected >=8 tagged surfaces, found ${surfaces.size}`);

	// `share_log_groups` drives the for_each behind both the metric filter and
	// its alarm, so a surface missing from it has neither.
	const block = alarms.match(/share_log_groups = \{([\s\S]*?)\n  \}/);
	assert.ok(block, 'could not find the share_log_groups locals block in alarms.tf');
	const registered = new Set(
		[...block[1].matchAll(/^\s*([a-z]+)\s*=/gm)].map((m) => m[1]),
	);
	const missing = [...surfaces].filter((s) => !registered.has(s)).sort();
	assert.deepEqual(
		missing,
		[],
		`these share surfaces log upstream_unreachable but have no metric filter, so the ` +
			`line lands in CloudWatch Logs and alarms nothing: ${missing.join(', ')}. Add them ` +
			'to share_log_groups in infra/modules/web-stack/alarms.tf.',
	);
});
