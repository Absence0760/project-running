import { execFileSync } from 'node:child_process';
import { readFileSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ALARMS_FILE,
  ALLOWED_STATUS_LAUNDERING,
  DISTRIBUTION_ALARMS,
  DEPENDABOT_FILE,
  INFRA_DIR,
  MODULE_FILE,
  TERRAFORM_WORKFLOW,
  VALIDATE_EXEMPT,
  compareSources,
  parseAlarms,
  parseDependabotTerraform,
  parseDistribution,
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
  { label: 'cf_4xx', kind: 'cf4xx', functions: [] },
  { label: 'cf_5xx', kind: 'cf5xx', functions: [] },
];

/** @param {Partial<import('./check_infra_coverage.mjs').Behaviour>} [over] */
function behaviour(over = {}) {
  return {
    pattern: '/share/run/*',
    origin: 'lambda-share-run',
    viewerProtocol: 'redirect-to-https',
    responseHeadersPolicy: 'aws_cloudfront_response_headers_policy.security.id',
    cachePolicy: 'aws_cloudfront_cache_policy.share_run.id',
    viewerRequestSources: ['local.www_redirect_associations'],
    ...over,
  };
}

/** @param {Partial<NonNullable<import('./check_infra_coverage.mjs').Distribution>>} [over] */
function distribution(over = {}) {
  return {
    originIds: ['s3-site', 'lambda-share-run'],
    originsMissingOac: [],
    insecureOrigins: [],
    behaviours: [
      behaviour({ pattern: '(default)', origin: 's3-site' }),
      behaviour(),
    ],
    headerPolicies: new Map([['security', { csp: true, permissionsPolicy: true }]]),
    errorResponses: [
      { errorCode: '403', responseCode: '200', responsePage: '/index.html' },
      { errorCode: '404', responseCode: '404', responsePage: '/index.html' },
    ],
    ...over,
  };
}

/**
 * @param {Partial<{ dirs: string[], matrix: string[], dependabot: string[],
 *                   functions: string[], alarms: import('./check_infra_coverage.mjs').Alarm[],
 *                   distribution: import('./check_infra_coverage.mjs').Distribution }>} [over]
 */
function run(over = {}) {
  return compareSources(
    over.dirs ?? DIRS,
    over.matrix ?? MATRIX,
    over.dependabot ?? DEPENDABOT,
    over.functions ?? FUNCTIONS,
    over.alarms ?? ALARMS,
    over.distribution === undefined ? distribution() : over.distribution,
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

test('dropping the distribution 5xx alarm fails', () => {
  const { errors } = run({ alarms: ALARMS.filter((a) => a.label !== 'cf_5xx') });
  assert.ok(has(errors, /no 5xxErrorRate alarm on the CloudFront distribution/), errors.join('\n'));
});

test('dropping the distribution 4xx alarm fails', () => {
  const { errors } = run({ alarms: ALARMS.filter((a) => a.label !== 'cf_4xx') });
  assert.ok(has(errors, /no 4xxErrorRate alarm on the CloudFront distribution/), errors.join('\n'));
});

test('every distribution alarm says what it is the only witness to', () => {
  for (const [kind, witnesses] of DISTRIBUTION_ALARMS) {
    assert.ok(witnesses.length > 30, `${kind} needs the reason, not a label`);
  }
});

test('parseAlarms classifies the two distribution alarms', () => {
  const src =
    'resource "aws_cloudwatch_metric_alarm" "cf4" {\n' +
    '  metric_name = "4xxErrorRate"\n  namespace   = "AWS/CloudFront"\n}\n\n' +
    'resource "aws_cloudwatch_metric_alarm" "cf5" {\n' +
    '  metric_name = "5xxErrorRate"\n  namespace   = "AWS/CloudFront"\n}\n';
  assert.deepEqual(
    parseAlarms(src).map((a) => a.kind),
    ['cf4xx', 'cf5xx'],
  );
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
    parseDistribution(readFileSync(MODULE_FILE, 'utf-8')),
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

// ───────────────── distribution behaviour coverage ─────────────────
//
// Each of these is the mutation the guard exists to catch, applied to the
// fixture: the property is stated once per behaviour by hand, CloudFront
// inherits none of them, and a page that renders is what the failure looks
// like from outside.

test('a behaviour with no response-headers policy is reported', () => {
  const { errors } = run({
    distribution: distribution({
      behaviours: [behaviour(), behaviour({ pattern: '/og/run/*', responseHeadersPolicy: null })],
    }),
  });
  assert.ok(has(errors, /"\/og\/run\/\*": no response_headers_policy_id/), errors.join('\n'));
});

test('a behaviour with no viewer-request function association is reported', () => {
  const { errors } = run({
    distribution: distribution({
      behaviours: [behaviour(), behaviour({ pattern: '/share/new/*', viewerRequestSources: [] })],
    }),
  });
  assert.ok(has(errors, /"\/share\/new\/\*": no viewer-request function_association/), errors.join('\n'));
});

test('two behaviours associating different viewer-request functions are reported', () => {
  const { errors } = run({
    distribution: distribution({
      behaviours: [
        behaviour(),
        behaviour({ pattern: '/og/run/*', viewerRequestSources: ['local.other_associations'] }),
      ],
    }),
  });
  assert.ok(has(errors, /2 different viewer-request functions/), errors.join('\n'));
});

test('an allow-all viewer protocol policy is reported', () => {
  const { errors } = run({
    distribution: distribution({
      behaviours: [behaviour(), behaviour({ pattern: '/og/run/*', viewerProtocol: 'allow-all' })],
    }),
  });
  assert.ok(has(errors, /viewer_protocol_policy is "allow-all"/), errors.join('\n'));
});

test('a behaviour pointing at an origin the distribution does not declare is reported', () => {
  const { errors } = run({
    distribution: distribution({
      behaviours: [behaviour(), behaviour({ pattern: '/og/run/*', origin: 'lambda-typo' })],
    }),
  });
  assert.ok(has(errors, /names no origin this distribution declares/), errors.join('\n'));
});

test('a behaviour with no cache policy is reported', () => {
  const { errors } = run({
    distribution: distribution({
      behaviours: [behaviour(), behaviour({ pattern: '/og/run/*', cachePolicy: null })],
    }),
  });
  assert.ok(has(errors, /no cache_policy_id/), errors.join('\n'));
});

test('two behaviours naming different response-headers policies are reported', () => {
  const { errors } = run({
    distribution: distribution({
      behaviours: [
        behaviour(),
        behaviour({
          pattern: '/og/run/*',
          responseHeadersPolicy: 'aws_cloudfront_response_headers_policy.lax.id',
        }),
      ],
    }),
  });
  assert.ok(has(errors, /2 different response-headers policies/), errors.join('\n'));
});

test('the shared response-headers policy losing its CSP is reported', () => {
  const { errors } = run({
    distribution: distribution({
      headerPolicies: new Map([['security', { csp: false, permissionsPolicy: true }]]),
    }),
  });
  assert.ok(has(errors, /no content_security_policy/), errors.join('\n'));
});

test('the shared response-headers policy losing Permissions-Policy is reported', () => {
  const { errors } = run({
    distribution: distribution({
      headerPolicies: new Map([['security', { csp: true, permissionsPolicy: false }]]),
    }),
  });
  assert.ok(has(errors, /no Permissions-Policy header/), errors.join('\n'));
});

test('an origin with no origin access control is reported', () => {
  const { errors } = run({
    distribution: distribution({ originsMissingOac: ['lambda-share-run'] }),
  });
  assert.ok(has(errors, /declares no origin_access_control_id/), errors.join('\n'));
});

test('an origin CloudFront may reach over plaintext http is reported', () => {
  const { errors } = run({ distribution: distribution({ insecureOrigins: ['lambda-share-run'] }) });
  assert.ok(has(errors, /origin_protocol_policy = "https-only"/), errors.join('\n'));
});

// A parse that stopped matching returns an empty behaviour list, and every
// per-behaviour assertion above then holds vacuously. That is the failure mode
// a source-reading guard has instead of a false negative.
test('a distribution whose behaviours could not be read fails rather than passing', () => {
  const { errors } = run({ distribution: distribution({ behaviours: [] }) });
  assert.ok(has(errors, /cache behaviour\(s\) were read/), errors.join('\n'));
});

test('no distribution at all fails rather than passing', () => {
  const { errors } = run({ distribution: null });
  assert.ok(has(errors, /no aws_cloudfront_distribution was read/), errors.join('\n'));
});

// ─────────────── parseDistribution against the real module ───────────────

test('parseDistribution reads every behaviour and origin of the committed distribution', () => {
  const dist = parseDistribution(readFileSync(MODULE_FILE, 'utf-8'));
  assert.ok(dist);
  assert.ok(dist.behaviours.length >= 18, `read only ${dist.behaviours.length} behaviours`);
  assert.ok(dist.originIds.length >= 9, `read only ${dist.originIds.length} origins`);
  assert.equal(dist.behaviours.filter((b) => b.pattern === '(default)').length, 1);
  // Every behaviour resolved all four fields — a parser returning nulls would
  // report eighteen findings rather than passing, but it would also mean the
  // reader below is not reading the file it thinks it is.
  for (const b of dist.behaviours) {
    assert.ok(b.origin, `${b.pattern}: no target_origin_id read`);
    assert.ok(b.viewerProtocol, `${b.pattern}: no viewer_protocol_policy read`);
    assert.ok(b.responseHeadersPolicy, `${b.pattern}: no response_headers_policy_id read`);
    assert.equal(b.viewerRequestSources.length, 1, `${b.pattern}: viewer-request associations`);
  }
});

test('the guard exits non-zero when a behaviour loses the security headers policy', () => {
  // End to end through main(), on a copy of the real module with the
  // response-headers policy struck off the /og/run/* behaviour — the one-line
  // omission a new behaviour is copy-pasted into existence with.
  const dir = mkdtempSync(join(tmpdir(), 'infra-coverage-dist-'));
  const src = readFileSync(MODULE_FILE, 'utf-8');
  const behaviour = /path_pattern\s*=\s*"\/og\/run\/\*"[\s\S]*?\n\s*response_headers_policy_id\s*=\s*[^\n]*\n/;
  assert.match(src, behaviour, 'the /og/run/* behaviour moved; re-anchor this test');
  const cut = src.replace(behaviour, (block) =>
    block.replace(/\n\s*response_headers_policy_id\s*=\s*[^\n]*\n/, '\n'),
  );
  assert.notEqual(cut, src, 'the strike-out did not change anything');
  const path = join(dir, 'main.tf');
  writeFileSync(path, cut);
  assert.throws(
    () =>
      execFileSync(process.execPath, ['scripts/check_infra_coverage.mjs'], {
        env: { ...process.env, INFRA_COVERAGE_MODULE: path },
        encoding: 'utf-8',
        stdio: 'pipe',
      }),
    /no response_headers_policy_id/,
  );
});

// ───────────────── claim 4: error-response honesty ─────────────────

test('the 404 mapping answering 404 with the shell body passes', () => {
  const { errors, ok } = run();
  assert.deepEqual(errors, []);
  assert.ok(
    ok.some((l) => /custom_error_response 403->200/.test(l)),
    ok.join('\n'),
  );
});

// The exact shape the distribution shipped until decisions § 1022: a Lambda's
// deliberate 404 answered 200, so ten /share/* paths were soft 404s.
test('a 404 laundered into a 200 fails', () => {
  const { errors } = run({
    distribution: distribution({
      errorResponses: [
        { errorCode: '403', responseCode: '200', responsePage: '/index.html' },
        { errorCode: '404', responseCode: '200', responsePage: '/index.html' },
      ],
    }),
  });
  assert.ok(has(errors, /maps 404 to 200/), errors.join('\n'));
  assert.equal(errors.length, 1);
});

test('a 5xx laundered into a 200 fails on the same rule', () => {
  const { errors } = run({
    distribution: distribution({
      errorResponses: [
        { errorCode: '403', responseCode: '200', responsePage: '/index.html' },
        { errorCode: '503', responseCode: '200', responsePage: '/maintenance.html' },
      ],
    }),
  });
  assert.ok(has(errors, /maps 503 to 200/), errors.join('\n'));
});

// A 4xx answered with another 4xx is not laundering — the reader is still told
// the request failed, which is the only property this claim is about.
test('a 4xx answered with a 4xx is not laundering', () => {
  const { errors } = run({
    distribution: distribution({
      errorResponses: [
        { errorCode: '403', responseCode: '200', responsePage: '/index.html' },
        { errorCode: '404', responseCode: '410', responsePage: '/index.html' },
      ],
    }),
  });
  assert.deepEqual(errors, []);
});

test('losing the declared 403 exemption fails as loudly as an undeclared one', () => {
  const { errors } = run({
    distribution: distribution({
      errorResponses: [{ errorCode: '404', responseCode: '404', responsePage: '/index.html' }],
    }),
  });
  assert.ok(has(errors, /ALLOWED_STATUS_LAUNDERING declares 403->200/), errors.join('\n'));
});

test('no custom_error_response at all is reported, not passed', () => {
  const { errors } = run({ distribution: distribution({ errorResponses: [] }) });
  assert.ok(has(errors, /no custom_error_response block was read/), errors.join('\n'));
});

test('an unreadable response_code is reported, not skipped', () => {
  const { errors } = run({
    distribution: distribution({
      errorResponses: [
        { errorCode: '403', responseCode: '200', responsePage: '/index.html' },
        { errorCode: '404', responseCode: null, responsePage: '/index.html' },
      ],
    }),
  });
  assert.ok(has(errors, /Both are required/), errors.join('\n'));
});

test('the committed module maps 404 to 404 and 403 to 200', () => {
  const dist = parseDistribution(readFileSync(MODULE_FILE, 'utf-8'));
  assert.ok(dist);
  assert.deepEqual(
    dist.errorResponses.map((e) => `${e.errorCode}->${e.responseCode}@${e.responsePage}`),
    ['403->200@/index.html', '404->404@/index.html'],
  );
});

// An exemption with no reason is a hole with a name. The map is the only place
// a status-laundering mapping is allowed to live, so its entries must say why.
test('every declared laundering exemption carries a reason', () => {
  assert.ok(ALLOWED_STATUS_LAUNDERING.size > 0);
  for (const [key, reason] of ALLOWED_STATUS_LAUNDERING) {
    assert.match(key, /^[45]\d\d->2\d\d$/);
    assert.ok(reason.length > 40, `${key} carries no reason`);
  }
});

test('the guard exits non-zero when the 404 mapping goes back to 200', () => {
  const dir = mkdtempSync(join(tmpdir(), 'infra-coverage-err-'));
  const src = readFileSync(MODULE_FILE, 'utf-8');
  const block = /custom_error_response \{\n(\s*)error_code\s*=\s*404\n\s*response_code\s*=\s*404\n/;
  assert.match(src, block, 'the 404 custom_error_response moved; re-anchor this test');
  const cut = src.replace(block, (b) => b.replace('response_code      = 404', 'response_code      = 200'));
  assert.notEqual(cut, src, 'the mutation did not change anything');
  const path = join(dir, 'main.tf');
  writeFileSync(path, cut);
  assert.throws(
    () =>
      execFileSync(process.execPath, ['scripts/check_infra_coverage.mjs'], {
        env: { ...process.env, INFRA_COVERAGE_MODULE: path },
        encoding: 'utf-8',
        stdio: 'pipe',
      }),
    /maps 404 to 200/,
  );
});
