// Unit tests for scripts/check_estate_slot.mjs.
//
// Measured the way the other source-reading guards are: the real tree is the
// positive control, and each case mutates an in-memory copy of it into one
// shape the guard exists to refuse. Every mutation must actually match, so a
// reworded source fails here instead of quietly testing an unmutated tree.
//
// Run: node --test scripts/check_estate_slot.test.mjs
// CI:  the `infra-guards` job in .github/workflows/ci.yml.

import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { SLOT_FILE, checkEstateSlot, collectFiles, slugAssignments, terraformSecretsPath } from './check_estate_slot.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const TREE = collectFiles(REPO_ROOT);
const fresh = () => new Map(TREE);

/**
 * @param {Map<string, string>} files @param {string} rel
 * @param {string | RegExp} from @param {string} to
 */
function edit(files, rel, from, to) {
	const src = files.get(rel);
	assert.ok(src !== undefined, `${rel} is not in the scanned set`);
	const next = src.replace(from, to);
	assert.notEqual(next, src, `${rel}: ${String(from)} matched nothing, so this case would test an unmutated tree`);
	files.set(rel, next);
}

/** @param {Map<string, string>} files @param {RegExp} pattern */
function findingsMatching(files, pattern) {
	return checkEstateSlot(files).findings.filter((f) => pattern.test(f));
}

test('the real tree is clean, and the scan actually read something', () => {
	const { slug, findings, counts } = checkEstateSlot(fresh());
	assert.deepEqual(findings, []);
	assert.equal(slug, 'threkir');
	assert.ok(counts.paths >= 10, `only ${counts.paths} estate paths seen`);
	assert.ok(counts.scripts >= 7, `only ${counts.scripts} bin scripts seen`);
});

test('a stale slug in estate.sh is caught against Terraform and every written path', () => {
	const files = fresh();
	edit(files, SLOT_FILE, 'ESTATE_SLUG="threkir"', 'ESTATE_SLUG="running"');
	assert.equal(findingsMatching(files, /infra\/envs\/(prod|preview)\/main\.tf:\d+: default secrets_path/).length, 2);
	assert.ok(findingsMatching(files, /^CLAUDE\.md:\d+: .*names the estate slot "threkir"/).length > 0);
});

test('estate.sh must assign the slug exactly once, to a plain slug', () => {
	let files = fresh();
	edit(files, SLOT_FILE, 'ESTATE_SLUG="threkir"', 'ESTATE_SLUG="threkir"\nESTATE_SLUG="running"');
	assert.equal(findingsMatching(files, /exactly once, found 2/).length, 1);

	files = fresh();
	edit(files, SLOT_FILE, 'ESTATE_SLUG="threkir"', 'ESTATE_SLUG="$(basename "$REPO_ROOT")"');
	assert.equal(findingsMatching(files, /must be a plain slug/).length, 1);

	files = fresh();
	files.delete(SLOT_FILE);
	assert.equal(findingsMatching(files, /bin\/lib\/estate\.sh: missing/).length, 1);
});

test('a Terraform default naming the wrong env, or none at all, is caught', () => {
	let files = fresh();
	edit(files, 'infra/envs/prod/main.tf', 'infra-secrets/threkir/prod.sops.yaml', 'infra-secrets/threkir/preview.sops.yaml');
	assert.equal(findingsMatching(files, /prod\/main\.tf:\d+: .*expected infra-secrets\/threkir\/prod\.sops\.yaml/).length, 1);

	files = fresh();
	edit(files, 'infra/envs/preview/main.tf', /secrets_path\s*=/, 'secrets_location =');
	assert.equal(findingsMatching(files, /preview\/main\.tf: no default `secrets_path`/).length, 1);
});

test('a bin script that resolves the estate on its own is caught', () => {
	for (const [line, pattern] of /** @type {[string, RegExp][]} */ ([
		['PROJECT_SLUG="running"', /assigns PROJECT_SLUG/],
		['\tlocal SOPS_CONFIG="$HOME/.sops.yaml"', /assigns SOPS_CONFIG/],
		['acct_file="${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}/threkir/aws-account"', /supplies its own INFRA_SECRETS_DIR default/],
		["grep -q 'KMS_THREKIR_PREVIEW_ARN_PLACEHOLDER' \"$SOPS_CONFIG\"", /names the placeholder KMS_THREKIR_PREVIEW_ARN_PLACEHOLDER/],
	])) {
		const files = fresh();
		edit(files, 'bin/secret-set.sh', 'set -euo pipefail\n', `set -euo pipefail\n${line}\n`);
		assert.equal(findingsMatching(files, new RegExp(`^bin/secret-set\\.sh:\\d+: ${pattern.source}`)).length, 1, line);
	}
});

test('a comment naming a placeholder is prose, not resolution', () => {
	const files = fresh();
	edit(files, 'bin/secret-set.sh', 'set -euo pipefail\n', 'set -euo pipefail\n# the estate still spells it KMS_RUNNING_PREVIEW_ARN_PLACEHOLDER\n');
	assert.deepEqual(checkEstateSlot(files).findings, []);
});

test('a stale slot in any written path shape is caught, in every scanned surface', () => {
	for (const [rel, from, to] of /** @type {[string, string | RegExp, string][]} */ ([
		['CLAUDE.md', 'under `threkir/{prod,preview}.sops.yaml`', 'under `running/{prod,preview}.sops.yaml`'],
		['bin/aws-preflight.sh', '../infra-secrets/threkir/aws-account', '../infra-secrets/running/aws-account'],
		['docs/ops/deployment.md', 'at `threkir/android-upload-keystore.sops.yaml`', 'at `running/android-upload-keystore.sops.yaml`'],
		['apps/mobile_android/deployment.md', 'at `threkir/android-upload-keystore.sops.yaml`', 'at `running/android-upload-keystore.sops.yaml`'],
		['infra/README.md', /seed threkir\/preview\.sops\.yaml/, 'seed running/preview.sops.yaml'],
		['infra/envs/prod/outputs.tf', 'to encrypt threkir/prod.sops.yaml.', 'to encrypt running/prod.sops.yaml.'],
		['infra/README.md', '--filename-override "$PWD/threkir/preview.sops.yaml"', '--filename-override "$PWD/running/preview.sops.yaml"'],
		['bin/aws-preflight.sh', '"$ESTATE_SLOT_DIR/aws-account")"', '"${INFRA_SECRETS_DIR:-$REPO_ROOT/../infra-secrets}/running/aws-account")"'],
	])) {
		const files = fresh();
		edit(files, rel, from, to);
		const hits = checkEstateSlot(files).findings.filter((f) => f.startsWith(`${rel}:`) && f.includes('names the estate slot "running"'));
		assert.equal(hits.length, 1, `${rel}: ${hits.join(' | ') || 'no finding'}`);
	}
});

test('records of past states are not in scope, and example templates are not estate files', () => {
	assert.equal(TREE.has('docs/architecture/decisions.md'), false);
	assert.equal(TREE.has('docs/product/followups.md'), false);
	const files = fresh();
	edit(files, 'infra/README.md', /$/, '\nThe template is `running/prod.sops.yaml.example`.\n');
	assert.deepEqual(checkEstateSlot(files).findings, []);
});

test('no estate path anywhere is reported as a scan that stopped matching', () => {
	/** @type {Map<string, string>} */
	const files = new Map();
	for (const [rel, src] of TREE) {
		if (rel === SLOT_FILE || rel.endsWith('/main.tf') || rel.endsWith('.sh')) files.set(rel, src.replace(/infra-secrets\/[^/\s`'"]+\//g, 'estate/').replace(/\b[a-z0-9-]+\/(?:prod|preview|<env>|android-upload-keystore)\.sops\.yaml/g, 'x').replace(/\b[a-z0-9-]+\/aws-account\b/g, 'x'));
	}
	assert.ok(checkEstateSlot(files).findings.some((f) => /patterns have stopped matching/.test(f)));
});

test('no bin/ scripts at all is reported as a scan that stopped matching', () => {
	const files = new Map([...TREE].filter(([rel]) => rel === SLOT_FILE || !/^bin\/.*\.sh$/.test(rel)));
	assert.ok(checkEstateSlot(files).findings.some((f) => /^bin\/: no scripts read/.test(f)));
});

test('slugAssignments and terraformSecretsPath read the shapes they are given', () => {
	assert.deepEqual(slugAssignments('# ESTATE_SLUG="no"\nESTATE_SLUG="threkir"\n  ESTATE_SLUG=other\n'), [
		{ value: 'threkir', line: 2 },
		{ value: 'other', line: 3 },
	]);
	assert.deepEqual(
		terraformSecretsPath('locals {\n  secrets_path = var.x != "" ? var.x : "${path.module}/../../../../infra-secrets/threkir/prod.sops.yaml"\n}\n'),
		{ line: 2, slot: 'threkir', name: 'prod' },
	);
	assert.equal(terraformSecretsPath('locals {}\n'), null);
});
