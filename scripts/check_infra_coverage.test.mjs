import { execFileSync } from 'node:child_process';
import { readFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ALARMS_FILE,
  DEPENDABOT_FILE,
  INFRA_DIR,
  MODULE_FILE,
  TERRAFORM_WORKFLOW,
  VALIDATE_EXEMPT,
  compareSources,
  parseAlarms,
  parseDependabotTerraform,
  parseModuleFunctions,
  parseStackMatrix,
  terraformDirs,
} from './check_infra_coverage.mjs';

// ─────────────────────────────── fixtures ───────────────────────────────

const DIRS = ['infra/bootstrap', 'infra/envs/prod', 'infra/modules/web-stack'];
const MATRIX = ['infra/bootstrap', 'infra/envs/prod'];
const DEPENDABOT = ['infra/bootstrap', 'infra/envs/prod', 'infra/modules/web-stack'];
const FUNCTIONS = ['coach', 'share_run'];

/** @type {import('./check_infra_coverage.mjs').Alarm[]} */
const ALARMS = [
  { label: 'coach_errors', kind: 'errors', functions: ['coach'] },
  { label: 'coach_p95', kind: 'p95', functions: ['coach'] },
  { label: 'share_errors', kind: 'errors', functions: ['share_run'] },
  { label: 'share_p95', kind: 'p95', functions: ['share_run'] },
  { label: 'throttles', kind: 'other', functions: ['coach'] },
];

/**
 * @param {Partial<{ dirs: string[], matrix: string[], dependabot: string[],
 *                   functions: string[], alarms: import('./check_infra_coverage.mjs').Alarm[] }>} [over]
 */
function run(over = {}) {
  return compareSources(
    over.dirs ?? DIRS,
    over.matrix ?? MATRIX,
    over.dependabot ?? DEPENDABOT,
    over.functions ?? FUNCTIONS,
    over.alarms ?? ALARMS,
  );
}

/** @param {string[]} errors @param {RegExp} re */
function has(errors, re) {
  return errors.some((e) => re.test(e));
}

// ──────────────────────────── the happy path ────────────────────────────

test('the fixture passes, so every failure below is the mutation', () => {
  const { errors } = run();
  assert.deepEqual(errors, []);
});

// ────────────────────────── stack coverage ──────────────────────────

test('a new stack nobody added to the matrix fails', () => {
  const { errors } = run({ dirs: [...DIRS, 'infra/waf'] });
  assert.ok(has(errors, /infra\/waf holds Terraform that no CI job validates/), errors.join('\n'));
});

test('a new stack nobody added to dependabot fails', () => {
  const { errors } = run({
    dirs: [...DIRS, 'infra/waf'],
    matrix: [...MATRIX, 'infra/waf'],
  });
  assert.ok(has(errors, /infra\/waf has no `package-ecosystem: "terraform"` entry/), errors.join('\n'));
});

test('a matrix entry naming a directory that is gone fails', () => {
  const { errors } = run({ matrix: [...MATRIX, 'infra/deleted'] });
  assert.ok(has(errors, /names infra\/deleted, which holds no \.tf files/), errors.join('\n'));
});

test('a dependabot entry naming a directory that is gone fails', () => {
  const { errors } = run({ dependabot: [...DEPENDABOT, 'infra/deleted'] });
  assert.ok(has(errors, /terraform ecosystem for infra\/deleted/), errors.join('\n'));
});

test('an exemption that is no longer needed fails', () => {
  const { errors } = run({ matrix: [...MATRIX, 'infra/modules/web-stack'] });
  assert.ok(has(errors, /both in the terraform workflow's stack matrix and exempt/), errors.join('\n'));
});

test('an exemption for a directory that no longer exists fails', () => {
  const { errors } = run({
    dirs: ['infra/bootstrap', 'infra/envs/prod'],
    dependabot: ['infra/bootstrap', 'infra/envs/prod'],
  });
  assert.ok(has(errors, /VALIDATE_EXEMPT exempts infra\/modules\/web-stack/), errors.join('\n'));
});

test('every exemption carries a reason, not a placeholder', () => {
  for (const [dir, reason] of VALIDATE_EXEMPT) {
    assert.ok(reason.length > 40, `${dir} needs the reason validate cannot run against it`);
  }
});

test('an unreadable matrix fails rather than certifying nothing', () => {
  const { errors } = run({ matrix: [] });
  assert.ok(has(errors, /could not read the `stack:` matrix/), errors.join('\n'));
});

// ────────────────────────── alarm coverage ──────────────────────────

test('a Lambda with no p95 alarm fails — the osrm-proxy gap', () => {
  const { errors } = run({
    alarms: ALARMS.filter((a) => a.label !== 'share_p95'),
  });
  assert.ok(has(errors, /share_run has no p95 alarm/), errors.join('\n'));
});

test('a Lambda with no error-rate alarm fails', () => {
  const { errors } = run({
    alarms: ALARMS.filter((a) => a.label !== 'coach_errors'),
  });
  assert.ok(has(errors, /coach has no errors alarm/), errors.join('\n'));
});

test('a new Lambda with no alarms at all fails on both', () => {
  const { errors } = run({ functions: [...FUNCTIONS, 'share_badge'] });
  assert.ok(has(errors, /share_badge has no errors and no p95 alarm/), errors.join('\n'));
});

test('a classifier that stopped matching fails rather than passing vacuously', () => {
  const { errors } = run({
    alarms: ALARMS.map((a) => ({ ...a, kind: /** @type {const} */ ('other') })),
  });
  assert.ok(has(errors, /classifier stopped matching/), errors.join('\n'));
});

test('no module Lambda at all fails rather than passing vacuously', () => {
  const { errors } = run({ functions: [] });
  assert.ok(has(errors, /pass vacuously/), errors.join('\n'));
});

// ─────────────────────────────── parsers ────────────────────────────────

test('parseStackMatrix reads the inline matrix and stops at its end', () => {
  const parsed = parseStackMatrix(
    'strategy:\n  matrix:\n    stack:\n      - infra/bootstrap\n      - infra/dns\n\nsteps:\n  - uses: x\n',
  );
  assert.deepEqual(parsed, ['infra/bootstrap', 'infra/dns']);
});

test('parseDependabotTerraform ignores other ecosystems', () => {
  const parsed = parseDependabotTerraform(
    '  - package-ecosystem: "npm"\n    directory: "/apps/web"\n' +
      '  - package-ecosystem: "terraform"\n    directory: "/infra/dns"\n',
  );
  assert.deepEqual(parsed, ['infra/dns']);
});

test('parseAlarms resolves a for_each alarm through its locals map', () => {
  const src =
    'locals {\n  share_lambdas = {\n' +
    '    run   = aws_lambda_function.share_run.function_name\n' +
    '    badge = aws_lambda_function.share_badge.function_name\n' +
    '  }\n}\n\n' +
    'resource "aws_cloudwatch_metric_alarm" "share_p95" {\n' +
    '  for_each           = local.share_lambdas\n' +
    '  metric_name        = "Duration"\n' +
    '  extended_statistic = "p95"\n' +
    '  dimensions = {\n    FunctionName = each.value\n  }\n}\n';
  const [alarm] = parseAlarms(src);
  assert.equal(alarm.kind, 'p95');
  assert.deepEqual(alarm.functions.sort(), ['share_badge', 'share_run']);
});

test('parseAlarms tells an error-rate alarm from a p95 one', () => {
  const src =
    'resource "aws_cloudwatch_metric_alarm" "e" {\n' +
    '  metric_query {\n    expression = "(errors / invocations) * 100"\n  }\n' +
    '  dimensions = {\n    FunctionName = aws_lambda_function.coach.function_name\n  }\n}\n';
  const [alarm] = parseAlarms(src);
  assert.equal(alarm.kind, 'errors');
  assert.deepEqual(alarm.functions, ['coach']);
});

// ───────────────────── the committed sources ─────────────────────

test('the committed infra/ tree is fully covered', () => {
  const { errors, ok } = compareSources(
    terraformDirs(INFRA_DIR),
    parseStackMatrix(readFileSync(TERRAFORM_WORKFLOW, 'utf-8')),
    parseDependabotTerraform(readFileSync(DEPENDABOT_FILE, 'utf-8')),
    parseModuleFunctions(readFileSync(MODULE_FILE, 'utf-8')),
    parseAlarms(readFileSync(ALARMS_FILE, 'utf-8')),
  );
  assert.deepEqual(errors, []);
  assert.ok(ok.length >= 12, 'a passing run that checked almost nothing is not a pass');
});

test('the parsers reach the committed sources', () => {
  const dirs = terraformDirs(INFRA_DIR);
  assert.ok(dirs.includes('infra/github-oidc'), dirs.join(', '));
  assert.ok(dirs.includes('infra/modules/web-stack'), dirs.join(', '));
  assert.ok(parseModuleFunctions(readFileSync(MODULE_FILE, 'utf-8')).length >= 8);
  const alarms = parseAlarms(readFileSync(ALARMS_FILE, 'utf-8'));
  assert.ok(alarms.some((a) => a.kind === 'errors'));
  assert.ok(alarms.some((a) => a.kind === 'p95'));
});

test('the guard exits non-zero when a source really is short', () => {
  // End to end, through main(): the alarms file as it stood before the
  // osrm-proxy p95 alarm landed is the real regression this must catch.
  const dir = mkdtempSync(join(tmpdir(), 'infra-coverage-'));
  const alarms = readFileSync(ALARMS_FILE, 'utf-8').replace(
    /resource "aws_cloudwatch_metric_alarm" "osrm_proxy_lambda_p95_duration" \{[\s\S]*?\n\}\n/,
    '',
  );
  const path = join(dir, 'alarms.tf');
  writeFileSync(path, alarms);
  assert.throws(
    () =>
      execFileSync(process.execPath, ['scripts/check_infra_coverage.mjs'], {
        env: { ...process.env, INFRA_COVERAGE_ALARMS: path },
        encoding: 'utf-8',
        stdio: 'pipe',
      }),
    /has no p95 alarm/,
  );
});
