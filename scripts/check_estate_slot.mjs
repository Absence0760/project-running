#!/usr/bin/env node
// Guardrail: the estate secrets slot is named in one place, and every path
// into it agrees with that name.
//
// Why this exists: decisions § 1615. The PRIVATE estate repo moved this
// project's slot from running/ to threkir/. The Terraform `secrets_file`
// defaults moved with it, because a stale default fails `terraform plan` with
// file-not-found. The bin/ operator scripts did not, because each named the
// slot for itself and a stale name fails quietly: sops-init.sh and
// secret-set.sh would have written into a slot no creation rule covers, and
// aws-preflight.sh stopped finding the account pin, which turned its
// wrong-account check from a hard failure into a warning. The rename moved the
// scripts' COMMENTS and not their values, and read as complete.
//
// bin/lib/estate.sh is now the one place the slot is named. Four claims:
//
//   1. estate.sh assigns ESTATE_SLUG exactly once, to a plain slug.
//   2. Each env's Terraform default `secrets_path` resolves inside that slot
//      and names its own env's file. Terraform is the half that fails loudly,
//      so it is what the scripts are held to.
//   3. No other bin/ script resolves the estate on its own: no assignment of
//      the slot, the estate directory or the sops config path, no
//      `${INFRA_SECRETS_DIR:-` default, and no `KMS_*_ARN_PLACEHOLDER` name.
//      The placeholder's name is the other spelling that moved: the scripts
//      found rules by it, and the estate's own tooling names placeholders by
//      a different convention.
//   4. Across the operator surface — bin/, infra/, docs/ops/, CLAUDE.md and
//      each app's deployment.md — every path written into the estate names
//      the slot: `infra-secrets/<slot>/…`, or a bare `<slot>/<env>.sops.yaml`
//      or `<slot>/aws-account`. decisions.md and followups.md record past
//      states and are not read.
//
// Offline by design: CI has no estate clone, no AWS credentials and no sops.
//
// Run: `node scripts/check_estate_slot.mjs`
// CI:  the `infra-guards` job in .github/workflows/ci.yml.
// Unit tests: `node --test scripts/check_estate_slot.test.mjs`

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const SLOT_FILE = 'bin/lib/estate.sh';
export const ENVS = ['prod', 'preview'];

const SCAN_DIRS = ['bin', 'infra', 'docs/ops'];
const SCAN_FILES = ['CLAUDE.md'];
const SKIP_DIRS = new Set(['.terraform', 'node_modules', 'dist', 'build']);
const TEXT_FILE = /\.(sh|md|tf|tfvars|hcl|ya?ml|json|mjs|js|ts|txt)$|\/\.[a-z]+ignore$/;
const SLUG = /^[a-z0-9][a-z0-9-]*$/;

/**
 * The files the four claims read, keyed by repo-relative path. Symlinks are not
 * followed: a local `terraform.tfvars` links into the estate clone itself.
 * @param {string} root
 * @returns {Map<string, string>}
 */
export function collectFiles(root) {
	/** @type {Map<string, string>} */
	const files = new Map();
	/** @param {string} rel */
	const add = (rel) => files.set(rel, readFileSync(join(root, rel), 'utf8'));
	/** @param {string} dir */
	const walk = (dir) => {
		for (const ent of readdirSync(join(root, dir), { withFileTypes: true })) {
			const rel = `${dir}/${ent.name}`;
			if (ent.isDirectory()) {
				if (!SKIP_DIRS.has(ent.name)) walk(rel);
			} else if (ent.isFile() && TEXT_FILE.test(rel)) {
				add(rel);
			}
		}
	};
	for (const dir of SCAN_DIRS) if (existsSync(join(root, dir))) walk(dir);
	for (const rel of SCAN_FILES) if (existsSync(join(root, rel))) add(rel);
	for (const app of readdirSync(join(root, 'apps'), { withFileTypes: true })) {
		const rel = `apps/${app.name}/deployment.md`;
		if (app.isDirectory() && existsSync(join(root, rel))) add(rel);
	}
	return files;
}

/**
 * @param {string} src
 * @returns {{ value: string, line: number }[]}
 */
export function slugAssignments(src) {
	/** @type {{ value: string, line: number }[]} */
	const out = [];
	src.split('\n').forEach((text, i) => {
		const m = /^\s*ESTATE_SLUG=(.*?)\s*$/.exec(text);
		if (m) out.push({ value: (m[1] ?? '').replace(/^(["'])(.*)\1$/, '$2'), line: i + 1 });
	});
	return out;
}

/**
 * The slot and file name a Terraform root's default `secrets_path` resolves to.
 * @param {string} src
 * @returns {{ line: number, slot: string | null, name: string | null } | null}
 */
export function terraformSecretsPath(src) {
	const lines = src.split('\n');
	for (let i = 0; i < lines.length; i++) {
		const text = lines[i] ?? '';
		if (!/^\s*secrets_path\s*=/.test(text)) continue;
		const m = /infra-secrets\/([^/"\s]+)\/([^/"\s]+)\.sops\.yaml/.exec(text);
		return { line: i + 1, slot: m?.[1] ?? null, name: m?.[2] ?? null };
	}
	return null;
}

/** @type {{ re: RegExp, what: (m: RegExpExecArray) => string }[]} */
const OWN_RESOLUTION = [
	{
		re: /(?:^|[\s;&|(])(?:export\s+|local\s+|readonly\s+|declare\s+(?:-\w+\s+)*)?(ESTATE_SLUG|ESTATE_SLOT_DIR|PROJECT_SLUG|SOPS_CONFIG|INFRA_SECRETS_DIR)=/,
		what: (m) => `assigns ${m[1]}`,
	},
	{ re: /\$\{INFRA_SECRETS_DIR:-/, what: () => 'supplies its own INFRA_SECRETS_DIR default' },
	{ re: /\bKMS_[A-Z0-9_]+_ARN_PLACEHOLDER\b/, what: (m) => `names the placeholder ${m[0]}` },
];

// The bare shapes skip a segment only when `infra-secrets/` precedes it, which
// the first pattern already counts. Skipping any preceding `/` instead hid
// `"$PWD/<slot>/…"` and `…/infra-secrets}/<slot>/aws-account` — the latter
// being the exact line that switched the preflight's account pin off.
const ESTATE_PATHS = [
	/infra-secrets\/([A-Za-z0-9][A-Za-z0-9._-]*)\//g,
	/(?<!infra-secrets\/)(?<![\w$.{}-])([a-z0-9][a-z0-9-]*)\/(?:prod|preview|<env>|\{prod,preview\}|android-upload-keystore)\.sops\.yaml(?![\w-]|\.\w)/g,
	/(?<!infra-secrets\/)(?<![\w$.{}-])([a-z0-9][a-z0-9-]*)\/aws-account\b/g,
];

/**
 * @param {Map<string, string>} files
 * @returns {{ slug: string | null, findings: string[], counts: { paths: number, pathFiles: number, scripts: number } }}
 */
export function checkEstateSlot(files) {
	/** @type {string[]} */
	const findings = [];
	const counts = { paths: 0, pathFiles: 0, scripts: 0 };

	const slotSrc = files.get(SLOT_FILE);
	const assigned = slotSrc === undefined ? [] : slugAssignments(slotSrc);
	if (slotSrc === undefined) {
		findings.push(`${SLOT_FILE}: missing — it is the one place the estate slot is named`);
	} else if (assigned.length !== 1) {
		findings.push(`${SLOT_FILE}: ESTATE_SLUG must be assigned exactly once, found ${assigned.length} (lines ${assigned.map((a) => a.line).join(', ') || 'none'})`);
	} else if (!SLUG.test(assigned[0]?.value ?? '')) {
		findings.push(`${SLOT_FILE}:${assigned[0]?.line}: ESTATE_SLUG must be a plain slug, got ${JSON.stringify(assigned[0]?.value)}`);
	}
	const slug = assigned.length === 1 && SLUG.test(assigned[0]?.value ?? '') ? (assigned[0]?.value ?? null) : null;
	if (slug === null) return { slug, findings, counts };

	for (const env of ENVS) {
		const rel = `infra/envs/${env}/main.tf`;
		const src = files.get(rel);
		const found = src === undefined ? null : terraformSecretsPath(src);
		if (found === null) {
			findings.push(`${rel}: no default \`secrets_path\` found — the anchor the scripts are held to has moved`);
		} else if (found.slot !== slug || found.name !== env) {
			findings.push(`${rel}:${found.line}: default secrets_path resolves to infra-secrets/${found.slot}/${found.name}.sops.yaml, expected infra-secrets/${slug}/${env}.sops.yaml`);
		}
	}

	for (const [rel, src] of files) {
		if (!rel.startsWith('bin/') || !rel.endsWith('.sh') || rel === SLOT_FILE) continue;
		counts.scripts++;
		src.split('\n').forEach((text, i) => {
			if (/^\s*#/.test(text)) return;
			for (const { re, what } of OWN_RESOLUTION) {
				const m = re.exec(text);
				if (m) findings.push(`${rel}:${i + 1}: ${what(m)} — resolve the estate through ${SLOT_FILE}`);
			}
		});
	}
	if (counts.scripts === 0) findings.push('bin/: no scripts read — the scan has stopped matching the tree');

	for (const [rel, src] of files) {
		let hit = false;
		src.split('\n').forEach((text, i) => {
			for (const re of ESTATE_PATHS) {
				for (const m of text.matchAll(re)) {
					hit = true;
					counts.paths++;
					if (m[1] !== slug) {
						findings.push(`${rel}:${i + 1}: \`${m[0]}\` names the estate slot "${m[1]}", but ${SLOT_FILE} names it "${slug}"`);
					}
				}
			}
		});
		if (hit) counts.pathFiles++;
	}
	if (counts.paths === 0) findings.push('no estate path found anywhere in scope — the patterns have stopped matching');

	return { slug, findings, counts };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const { slug, findings, counts } = checkEstateSlot(collectFiles(REPO_ROOT));
	if (findings.length > 0) {
		for (const f of findings) console.error(f);
		console.error(`\n${findings.length} estate slot finding(s).`);
		process.exit(1);
	}
	console.log(
		`estate slot "${slug}": ${ENVS.length} Terraform defaults, ${counts.paths} estate paths across ${counts.pathFiles} files, and ${counts.scripts} bin/ scripts agree with ${SLOT_FILE}`,
	);
}
