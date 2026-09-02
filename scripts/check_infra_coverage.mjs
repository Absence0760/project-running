#!/usr/bin/env node
// Guardrail: nothing under infra/ is unwatched — every stack is validated and
// dependency-tracked, and every Lambda the web stack creates is alarmed.
//
// Both halves close the same gap in different places: a hand-maintained list
// that has to be edited for a new thing to be covered, with nothing failing
// when it is not.
//
//   1. Stack coverage. `.github/workflows/terraform.yml` expands its stacks as
//      an inline `stack:` matrix and its header says "when adding a new stack:
//      append it to the matrix below AND add a terraform ecosystem entry to
//      .github/dependabot.yml". A stack absent from the matrix gets no `fmt`,
//      no `validate` and no Trivy verdict of its own; one absent from
//      dependabot never hears about a provider CVE. Neither absence shows up
//      as a red check — the workflow simply has one fewer green row than it
//      could have, which is invisible next to the twenty it does have.
//
//      infra/modules/web-stack is the one directory that cannot be validated
//      on its own: it takes an `aws.us_east_1` aliased provider from its
//      caller, so a standalone `terraform validate` fails with "Provider
//      configuration not present" (measured, not assumed). It is exempt here
//      WITH that reason, and the exemption fails if it ever stops being needed.
//
//   2. Lambda alarm coverage. A failing Lambda origin on this distribution is
//      invisible. CloudFront models custom error responses per distribution
//      rather than per behaviour, so the SPA `403/404 → /index.html at 200`
//      fallback rewrites a Lambda-origin error too — issue #590 measured
//      exactly that, a Function URL 403ing before invocation while the page
//      still rendered. The CloudWatch alarms are the only signal those
//      failures have, and osrm-proxy shipped without the p95 one its own
//      comment claimed it mirrored from generate-route.
//
// Offline by design: a directory listing and three files. No AWS credentials,
// no `terraform init`.
//
// Run: `node scripts/check_infra_coverage.mjs`
// CI:  the `infra-guards` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_infra_coverage.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { hclResources, nestedBlock, stripComments } from './hcl_lex.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const INFRA_DIR = process.env.INFRA_COVERAGE_DIR ?? join(REPO_ROOT, 'infra');
export const TERRAFORM_WORKFLOW =
  process.env.INFRA_COVERAGE_WORKFLOW ??
  join(REPO_ROOT, '.github/workflows/terraform.yml');
export const DEPENDABOT_FILE =
  process.env.INFRA_COVERAGE_DEPENDABOT ??
  join(REPO_ROOT, '.github/dependabot.yml');
export const MODULE_FILE =
  process.env.INFRA_COVERAGE_MODULE ??
  join(REPO_ROOT, 'infra/modules/web-stack/main.tf');
export const ALARMS_FILE =
  process.env.INFRA_COVERAGE_ALARMS ??
  join(REPO_ROOT, 'infra/modules/web-stack/alarms.tf');

/// Directories `terraform validate` cannot be run against on their own, and
/// why. An entry that stops being needed fails as loudly as a missing one.
export const VALIDATE_EXEMPT = new Map([
  [
    'infra/modules/web-stack',
    'a module taking an aws.us_east_1 aliased provider from its caller; a standalone validate ' +
      'fails with "Provider configuration not present". Validated transitively by envs/prod + envs/preview.',
  ],
]);

/**
 * @typedef {'errors' | 'p95' | 'cf4xx' | 'cf5xx' | 'other'} AlarmKind
 * @typedef {{ label: string, kind: AlarmKind, functions: string[] }} Alarm
 */

/// The two distribution-level alarms, and what each one is the only witness to.
/// alarms.tf's own first line and apps/web/deployment.md both claimed these
/// existed while every alarm in the file was per-Lambda; the observability bar
/// deployment.md sets for v1 — "someone gets paged when the site is down" — was
/// met by nothing (decisions § 890).
/** @type {Map<AlarmKind, string>} */
export const DISTRIBUTION_ALARMS = new Map([
  ['cf4xx', 'a step change in 4xx — mass auth failure, a behaviour that stopped routing, an SPA fallback that stopped falling back'],
  ['cf5xx', 'an origin failing for a share of viewers, whichever one it is'],
]);

// ─────────────────────────────── parsers ────────────────────────────────

/// Every directory under `infra/` holding at least one `.tf` file, as a
/// repo-relative path with forward slashes.
/**
 * @param {string} root absolute path to infra/
 * @param {(dir: string) => string[]} [list] injectable for the tests
 * @returns {string[]}
 */
export function terraformDirs(root, list = (d) => readdirSync(d)) {
  /** @type {string[]} */
  const out = [];
  /** @param {string} abs @param {string} rel */
  const walk = (abs, rel) => {
    /** @type {string[]} */
    let entries;
    try {
      entries = list(abs);
    } catch {
      return;
    }
    if (entries.some((e) => e.endsWith('.tf'))) out.push(rel);
    for (const entry of entries) {
      if (entry.startsWith('.') || entry.includes('.')) continue;
      walk(join(abs, entry), `${rel}/${entry}`);
    }
  };
  walk(root, 'infra');
  return out.sort();
}

/// The `stack:` matrix of the terraform workflow, in file order.
/**
 * @param {string} src
 * @returns {string[]}
 */
export function parseStackMatrix(src) {
  const head = src.match(/^\s*stack:\s*$/m);
  if (!head || head.index === undefined) return [];
  const rest = src.slice(head.index + head[0].length);
  /** @type {string[]} */
  const out = [];
  for (const line of rest.split('\n')) {
    if (line.trim() === '') continue;
    const item = line.match(/^\s*-\s*(\S+)\s*$/);
    if (!item) break;
    out.push(item[1].replace(/^['"]|['"]$/g, ''));
  }
  return out;
}

/// Every `directory:` declared under a `package-ecosystem: "terraform"` entry,
/// normalised to a repo-relative path with no leading slash.
/**
 * @param {string} src
 * @returns {string[]}
 */
export function parseDependabotTerraform(src) {
  /** @type {string[]} */
  const out = [];
  const blocks = src.split(/\n\s*-\s*package-ecosystem:/);
  for (const block of blocks.slice(1)) {
    const eco = block.match(/^\s*["']?([a-z-]+)["']?/)?.[1];
    if (eco !== 'terraform') continue;
    const dir = block.match(/^\s*directory:\s*["']?([^"'\n]+)["']?/m)?.[1];
    if (dir === undefined) continue;
    out.push(dir.trim().replace(/^\//, ''));
  }
  return out;
}

/// Every `aws_lambda_function` label in the module.
/**
 * @param {string} raw
 * @returns {string[]}
 */
export function parseModuleFunctions(raw) {
  return hclResources(stripComments(raw), 'aws_lambda_function').map((r) => r.label);
}

/// Every metric alarm in alarms.tf, classified and resolved to the Lambda
/// labels it watches. An alarm driven by `for_each = local.<map>` resolves
/// through that map, so the five share Lambdas are read as five and not as one
/// `each.value` nobody can attribute.
/**
 * @param {string} raw
 * @returns {Alarm[]}
 */
export function parseAlarms(raw) {
  const src = stripComments(raw);

  /** @type {Map<string, string[]>} */
  const localMaps = new Map();
  for (const m of src.matchAll(/^locals\s*\{/gm)) {
    const body = nestedBlock(src.slice(m.index), /^locals\s*\{/);
    if (body === null) continue;
    for (const entry of body.matchAll(
      /^\s*([A-Za-z0-9_]+)\s*=\s*\{/gm,
    )) {
      const mapBody = nestedBlock(
        body.slice(entry.index),
        new RegExp(`${entry[1]}\\s*=\\s*\\{`),
      );
      if (mapBody === null) continue;
      localMaps.set(entry[1], [
        ...new Set(
          [...mapBody.matchAll(/aws_lambda_function\.([A-Za-z0-9_]+)\./g)].map(
            (x) => x[1],
          ),
        ),
      ]);
    }
  }

  /** @type {Alarm[]} */
  const out = [];
  for (const { label, body } of hclResources(src, 'aws_cloudwatch_metric_alarm')) {
    /** @type {AlarmKind} */
    let kind = 'other';
    if (/namespace\s*=\s*"AWS\/CloudFront"/.test(body)) {
      if (/metric_name\s*=\s*"4xxErrorRate"/.test(body)) kind = 'cf4xx';
      else if (/metric_name\s*=\s*"5xxErrorRate"/.test(body)) kind = 'cf5xx';
    } else if (
      /extended_statistic\s*=\s*"p95"/.test(body) &&
      /metric_name\s*=\s*"Duration"/.test(body)
    ) {
      kind = 'p95';
    } else if (/\(\s*errors\s*\/\s*invocations\s*\)\s*\*\s*100/.test(body)) {
      kind = 'errors';
    }

    let functions = [
      ...new Set(
        [...body.matchAll(/aws_lambda_function\.([A-Za-z0-9_]+)\./g)].map((x) => x[1]),
      ),
    ];
    const each = body.match(/^\s*for_each\s*=\s*local\.([A-Za-z0-9_]+)/m)?.[1];
    if (functions.length === 0 && each !== undefined) {
      functions = localMaps.get(each) ?? [];
    }
    out.push({ label, kind, functions });
  }
  return out;
}

// ────────────────────────────── comparison ──────────────────────────────

/**
 * @param {string[]} dirs
 * @param {string[]} matrix
 * @param {string[]} dependabot
 * @param {string[]} functions
 * @param {Alarm[]} alarms
 * @returns {{ errors: string[], ok: string[] }}
 */
export function compareSources(dirs, matrix, dependabot, functions, alarms) {
  /** @type {string[]} */
  const errors = [];
  /** @type {string[]} */
  const ok = [];

  if (dirs.length === 0) {
    errors.push(
      'no Terraform directory was found under infra/ — the stack-coverage half checked nothing.',
    );
  }
  if (matrix.length === 0) {
    errors.push(
      "could not read the `stack:` matrix out of the terraform workflow — the matrix moved, and " +
        'until this parses again an unvalidated stack reads as covered.',
    );
  }

  const matrixSet = new Set(matrix);
  const dependabotSet = new Set(dependabot);
  /** @type {Set<string>} */
  const usedExemptions = new Set();

  for (const dir of dirs) {
    const exemption = VALIDATE_EXEMPT.get(dir);
    if (matrixSet.has(dir)) {
      if (exemption !== undefined) {
        errors.push(
          `${dir} is both in the terraform workflow's stack matrix and exempt from it. One of the ` +
            'two is wrong; if it validates now, drop the exemption.',
        );
      }
      ok.push(`${dir}: fmt + validate + Trivy in CI`);
    } else if (exemption !== undefined) {
      usedExemptions.add(dir);
      ok.push(`${dir}: exempt from validate (${exemption.split(';')[0]})`);
    } else {
      errors.push(
        `${dir} holds Terraform that no CI job validates. Add it to the \`stack:\` matrix in ` +
          '.github/workflows/terraform.yml, or to VALIDATE_EXEMPT in this guard with the reason ' +
          'validate cannot run against it.',
      );
    }

    if (!dependabotSet.has(dir)) {
      errors.push(
        `${dir} has no \`package-ecosystem: "terraform"\` entry in .github/dependabot.yml, so a ` +
          'provider CVE never opens a PR against it. Its .terraform.lock.hcl pins a version ' +
          'nothing will ever move.',
      );
    }
  }

  const dirSet = new Set(dirs);
  for (const stack of matrix) {
    if (!dirSet.has(stack)) {
      errors.push(
        `the terraform workflow's stack matrix names ${stack}, which holds no .tf files. The job ` +
          'fails at `terraform fmt` with a confusing error, or worse, passes on an empty directory.',
      );
    }
  }
  for (const dir of dependabot) {
    if (!dirSet.has(dir)) {
      errors.push(
        `.github/dependabot.yml declares a terraform ecosystem for ${dir}, which holds no .tf files.`,
      );
    }
  }
  for (const [dir, reason] of VALIDATE_EXEMPT) {
    if (!usedExemptions.has(dir)) {
      errors.push(
        `VALIDATE_EXEMPT exempts ${dir} ("${reason.split(';')[0]}") but that directory is not an ` +
          'unmatrixed Terraform directory any more. Drop the entry.',
      );
    }
  }

  // ── Lambda alarm coverage ──
  if (functions.length === 0) {
    errors.push(
      'no aws_lambda_function was read from the web-stack module — the alarm-coverage half would ' +
        'pass vacuously.',
    );
  }
  /** @type {{ errors: Set<string>, p95: Set<string> }} */
  const watched = { errors: new Set(), p95: new Set() };
  for (const alarm of alarms) {
    if (alarm.kind !== 'errors' && alarm.kind !== 'p95') continue;
    for (const fn of alarm.functions) watched[alarm.kind].add(fn);
  }

  const kinds = new Set(alarms.map((a) => a.kind));
  for (const [kind, witnesses] of DISTRIBUTION_ALARMS) {
    if (!kinds.has(kind)) {
      errors.push(
        `no ${kind === 'cf4xx' ? '4xxErrorRate' : '5xxErrorRate'} alarm on the CloudFront ` +
          `distribution. It is the only witness to ${witnesses}; every other alarm in the file ` +
          'is scoped to one Lambda and cannot see the distribution at all.',
      );
    } else {
      ok.push(`CloudFront distribution: ${kind === 'cf4xx' ? '4xx' : '5xx'} rate alarm`);
    }
  }
  if (watched.errors.size === 0 && watched.p95.size === 0 && functions.length > 0) {
    errors.push(
      'no alarm in alarms.tf resolved to any Lambda — the classifier stopped matching, and every ' +
        'function below would read as unwatched or as watched by accident.',
    );
  }
  for (const fn of functions) {
    const missing = /** @type {const} */ (['errors', 'p95']).filter(
      (k) => !watched[k].has(fn),
    );
    if (missing.length === 0) {
      ok.push(`aws_lambda_function.${fn}: error-rate + p95 alarms`);
      continue;
    }
    errors.push(
      `aws_lambda_function.${fn} has no ${missing.join(' and no ')} alarm. A Lambda-origin failure ` +
        "on this distribution is invisible — CloudFront's per-distribution 403/404 → /index.html " +
        'fallback rewrites it to a 200 shell — so the alarm is the only signal it has.',
    );
  }

  return { errors, ok };
}

export function main() {
  const { errors, ok } = compareSources(
    terraformDirs(INFRA_DIR),
    parseStackMatrix(readFileSync(TERRAFORM_WORKFLOW, 'utf-8')),
    parseDependabotTerraform(readFileSync(DEPENDABOT_FILE, 'utf-8')),
    parseModuleFunctions(readFileSync(MODULE_FILE, 'utf-8')),
    parseAlarms(readFileSync(ALARMS_FILE, 'utf-8')),
  );

  for (const line of ok) console.log(`[OK] ${line}`);
  for (const line of errors) console.error(`[FAIL] ${line}`);

  if (errors.length > 0) {
    console.error(`\n${errors.length} coverage gap(s) under infra/.`);
    return 1;
  }
  console.log(`\n${ok.length} infra/ coverage claim(s) hold.`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
