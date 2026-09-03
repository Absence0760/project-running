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
//   2. Distribution behaviour coverage. The CloudFront distribution carries
//      eighteen cache behaviours and every one of them re-states, by hand, the
//      three properties that make it safe: the security response-headers policy
//      (the CSP, HSTS, X-Frame-Options and Permissions-Policy live there and
//      nowhere else), an https viewer-protocol policy, and the viewer-request
//      function association that redirects `www.` to the apex. None of the
//      three is inherited — CloudFront applies a response-headers policy and an
//      edge function PER BEHAVIOUR — so a nineteenth behaviour that omits one
//      serves that path with no CSP at all, or serves the whole site at a
//      second host on that path. `www_redirect.js` had already shipped serving
//      `WWW.threkir.com` for a year with nothing executing it (decisions § 894);
//      this is the same function stopping at a path instead of at a casing, and
//      the failure looks identical from the outside: a page that renders.
//
//   3. Lambda alarm coverage. A failing Lambda origin on this distribution is
//      invisible. CloudFront models custom error responses per distribution
//      rather than per behaviour, so the SPA `403/404 → /index.html at 200`
//      fallback rewrites a Lambda-origin error too — issue #590 measured
//      exactly that, a Function URL 403ing before invocation while the page
//      still rendered. The CloudWatch alarms are the only signal those
//      failures have, and osrm-proxy shipped without the p95 one its own
//      comment claimed it mirrored from generate-route.
//
//   4. Error-response honesty. `custom_error_response` is the one place on this
//      distribution where a status code can be laundered, and because it is
//      distribution-wide it launders EVERY origin's at once. A mapping that
//      answers a 4xx/5xx with a 2xx tells a crawler the page is fine — which is
//      what the 404 -> 200 mapping did to ten `/share/*` paths, turning every
//      private, deleted or never-existing entity into a soft 404 Google was
//      invited to index, with the `noindex` that would have said otherwise
//      sitting in a Lambda body the rewrite discards (decisions § 1022). One
//      such mapping is legitimate and is declared here with its reason: the
//      SPA's 403 deep-link path, where S3's GetObject-only bucket policy makes
//      a missing key a 403 and every dynamic client route a missing key. Any
//      other status-laundering mapping fails, and a declared exemption nothing
//      uses fails too — the RESOURCELESS_ACTIONS shape, one file over.
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

import { hclResources, nestedBlock, nestedBlocks, stripComments } from './hcl_lex.mjs';

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

/// Viewer-protocol policies that cannot serve a plaintext response. CloudFront
/// also accepts `allow-all`, which answers http:// directly and is what the
/// HSTS header in the response-headers policy exists to stop a browser ever
/// asking for again.
export const HTTPS_VIEWER_POLICIES = new Set(['redirect-to-https', 'https-only']);

/**
 * @typedef {{
 *   pattern: string,
 *   origin: string | null,
 *   viewerProtocol: string | null,
 *   responseHeadersPolicy: string | null,
 *   cachePolicy: string | null,
 *   viewerRequestSources: string[],
 * }} Behaviour
 * @typedef {{
 *   originIds: string[],
 *   originsMissingOac: string[],
 *   insecureOrigins: string[],
 *   behaviours: Behaviour[],
 *   headerPolicies: Map<string, { csp: boolean, permissionsPolicy: boolean }>,
 *   errorResponses: ErrorResponse[],
 * } | null} Distribution
 * @typedef {{ errorCode: string | null, responseCode: string | null, responsePage: string | null }} ErrorResponse
 */

/// The one status-laundering `custom_error_response` this distribution is
/// allowed, keyed `<error_code>-><response_code>`, with the reason. An entry
/// here that no block uses fails, so the exemption cannot outlive its grant.
export const ALLOWED_STATUS_LAUNDERING = new Map([
  [
    '403->200',
    'the SPA deep-link path: the site bucket grants s3:GetObject and no s3:ListBucket, so a missing key is 403 AccessDenied and every dynamic client route (/dashboard, /runs/<id>, /u/<id>) arrives as one',
  ],
]);

/** @param {string} body @param {string} key */
function attr(body, key) {
  return body.match(new RegExp(`^\\s*${key}\\s*=\\s*(.+?)\\s*$`, 'm'))?.[1] ?? null;
}

/** @param {string | null} value */
function unquote(value) {
  return value === null ? null : value.replace(/^"|"$/g, '');
}

/// The distribution's origins and cache behaviours, plus what each
/// response-headers policy in the module actually carries. Null when no
/// `aws_cloudfront_distribution` could be read at all, which the caller reports
/// rather than treating as "nothing to check".
/**
 * @param {string} raw
 * @returns {Distribution}
 */
export function parseDistribution(raw) {
  const src = stripComments(raw);
  const dist = hclResources(src, 'aws_cloudfront_distribution')[0];
  if (dist === undefined) return null;

  /** @type {string[]} */
  const originIds = [];
  /** @type {string[]} */
  const originsMissingOac = [];
  /** @type {string[]} */
  const insecureOrigins = [];
  for (const { body } of nestedBlocks(dist.body, /(?:^|\n)\s*origin\s*\{/)) {
    const id = unquote(attr(body, 'origin_id')) ?? '(unnamed)';
    originIds.push(id);
    if (attr(body, 'origin_access_control_id') === null) originsMissingOac.push(id);
    const custom = nestedBlock(body, /custom_origin_config\s*\{/);
    if (custom !== null && unquote(attr(custom, 'origin_protocol_policy')) !== 'https-only') {
      insecureOrigins.push(id);
    }
  }

  /** @type {Behaviour[]} */
  const behaviours = [];
  for (const { label, body } of nestedBlocks(
    dist.body,
    /(?:^|\n)\s*(?:default|ordered)_cache_behavior\s*\{/,
  )) {
    /** @type {string[]} */
    const viewerRequestSources = [];
    for (const assoc of nestedBlocks(
      body,
      /(?:^|\n)\s*(?:dynamic\s+"function_association"|function_association)\s*\{/,
    )) {
      const content = nestedBlock(assoc.body, /content\s*\{/) ?? assoc.body;
      if (unquote(attr(content, 'event_type')) !== 'viewer-request') continue;
      viewerRequestSources.push(
        attr(assoc.body, 'for_each') ?? attr(content, 'function_arn') ?? '(unreadable)',
      );
    }
    behaviours.push({
      pattern: unquote(attr(body, 'path_pattern')) ?? (label.includes('default') ? '(default)' : '(unnamed)'),
      origin: unquote(attr(body, 'target_origin_id')),
      viewerProtocol: unquote(attr(body, 'viewer_protocol_policy')),
      responseHeadersPolicy: attr(body, 'response_headers_policy_id'),
      cachePolicy: attr(body, 'cache_policy_id'),
      viewerRequestSources,
    });
  }

  /** @type {Map<string, { csp: boolean, permissionsPolicy: boolean }>} */
  const headerPolicies = new Map();
  for (const { label, body } of hclResources(src, 'aws_cloudfront_response_headers_policy')) {
    headerPolicies.set(label, {
      csp: nestedBlock(body, /content_security_policy\s*\{/) !== null,
      permissionsPolicy: /header\s*=\s*"Permissions-Policy"/.test(body),
    });
  }

  /** @type {ErrorResponse[]} */
  const errorResponses = [];
  for (const { body } of nestedBlocks(dist.body, /(?:^|\n)\s*custom_error_response\s*\{/)) {
    errorResponses.push({
      errorCode: unquote(attr(body, 'error_code')),
      responseCode: unquote(attr(body, 'response_code')),
      responsePage: unquote(attr(body, 'response_page_path')),
    });
  }

  return {
    originIds,
    originsMissingOac,
    insecureOrigins,
    behaviours,
    headerPolicies,
    errorResponses,
  };
}

// ────────────────────────────── comparison ──────────────────────────────

/**
 * @param {string[]} dirs
 * @param {string[]} matrix
 * @param {string[]} dependabot
 * @param {string[]} functions
 * @param {Alarm[]} alarms
 * @param {Distribution} distribution
 * @returns {{ errors: string[], ok: string[] }}
 */
export function compareSources(dirs, matrix, dependabot, functions, alarms, distribution) {
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

  distributionCoverage(distribution, errors, ok);

  return { errors, ok };
}

/// The third half: every cache behaviour restates the security policy, the
/// https viewer policy and the viewer-request function by hand, and CloudFront
/// inherits none of the three.
/**
 * @param {Distribution} distribution
 * @param {string[]} errors
 * @param {string[]} ok
 */
function distributionCoverage(distribution, errors, ok) {
  if (distribution === null) {
    errors.push(
      'no aws_cloudfront_distribution was read from the web-stack module — the behaviour-coverage ' +
        'half checked nothing, and a behaviour serving a path with no CSP would read as covered.',
    );
    return;
  }
  const {
    behaviours,
    originIds,
    originsMissingOac,
    insecureOrigins,
    headerPolicies,
    errorResponses,
  } = distribution;

  // ── 4. no custom_error_response launders a 4xx/5xx into a 2xx ──
  if (errorResponses.length === 0) {
    errors.push(
      'no custom_error_response block was read from the distribution. The SPA needs the 403 one to ' +
        'serve a deep link at all, so a count of zero means this scan stopped matching rather than ' +
        'that the mappings are gone.',
    );
  }
  /** @type {Set<string>} */
  const launderingSeen = new Set();
  for (const { errorCode, responseCode, responsePage } of errorResponses) {
    if (errorCode === null || responseCode === null) {
      errors.push(
        `a custom_error_response was read with error_code=${JSON.stringify(errorCode)} and ` +
          `response_code=${JSON.stringify(responseCode)}. Both are required to tell an honest ` +
          'mapping from a laundering one, and an unreadable one is not a passing one.',
      );
      continue;
    }
    if (!/^[45]/.test(errorCode) || !/^2/.test(responseCode)) continue;
    const key = `${errorCode}->${responseCode}`;
    launderingSeen.add(key);
    const reason = ALLOWED_STATUS_LAUNDERING.get(key);
    if (reason === undefined) {
      errors.push(
        `custom_error_response maps ${errorCode} to ${responseCode} ` +
          `(${responsePage ?? 'no page'}). custom_error_response is DISTRIBUTION-wide, so that ` +
          "rewrites every Lambda origin's deliberate error into a success as well: a crawler is " +
          'told the page is fine, and any `noindex` the origin sent lives in a body this mapping ' +
          'discards. Answer the honest status with the shell body (response_code = error_code) ' +
          'unless the mapping is the SPA deep-link one, which is declared in ' +
          'ALLOWED_STATUS_LAUNDERING with its reason. decisions § 1022.',
      );
    } else {
      ok.push(`custom_error_response ${key}: ${reason}`);
    }
  }
  for (const [key, reason] of ALLOWED_STATUS_LAUNDERING) {
    if (!launderingSeen.has(key)) {
      errors.push(
        `ALLOWED_STATUS_LAUNDERING declares ${key} (${reason}) and no custom_error_response does ` +
          'it. A stale exemption reads as a deliberate decision long after the mapping it excused ' +
          'is gone.',
      );
    }
  }
  if (behaviours.length < 2) {
    errors.push(
      `only ${behaviours.length} cache behaviour(s) were read from the distribution. It carries a ` +
        'default plus one per routed path; a count this low means the block scan stopped matching ' +
        'and every behaviour below went unchecked.',
    );
    return;
  }

  for (const id of originsMissingOac) {
    errors.push(
      `distribution origin ${JSON.stringify(id)} declares no origin_access_control_id, so ` +
        'CloudFront reaches it unsigned. An S3 origin then needs a public bucket policy and a ' +
        'Lambda Function URL needs authorization_type=NONE — both make the origin reachable ' +
        'without going through this distribution at all.',
    );
  }
  for (const id of insecureOrigins) {
    errors.push(
      `distribution origin ${JSON.stringify(id)} does not set origin_protocol_policy = "https-only", ` +
        'so the CloudFront-to-origin leg can fall back to plaintext http.',
    );
  }

  const originSet = new Set(originIds);
  /** @type {Set<string>} */
  const policies = new Set();
  /** @type {Set<string>} */
  const viewerRequestSources = new Set();

  for (const b of behaviours) {
    const at = `cache behaviour ${JSON.stringify(b.pattern)}`;
    if (b.origin === null || !originSet.has(b.origin)) {
      errors.push(
        `${at}: target_origin_id ${JSON.stringify(b.origin)} names no origin this distribution ` +
          'declares.',
      );
    }
    if (b.viewerProtocol === null || !HTTPS_VIEWER_POLICIES.has(b.viewerProtocol)) {
      errors.push(
        `${at}: viewer_protocol_policy is ${JSON.stringify(b.viewerProtocol)}. Only ` +
          `${[...HTTPS_VIEWER_POLICIES].join(' / ')} keep this path off plaintext http.`,
      );
    }
    if (b.cachePolicy === null) {
      errors.push(
        `${at}: no cache_policy_id. The legacy forwarded_values form it falls back to has its own ` +
          'cookie and header defaults, which is not a decision anyone made here.',
      );
    }
    if (b.responseHeadersPolicy === null) {
      errors.push(
        `${at}: no response_headers_policy_id. CloudFront applies a response-headers policy PER ` +
          'BEHAVIOUR and inherits nothing from the default one, so this path answers with no CSP, ' +
          'no HSTS, no X-Frame-Options and no Permissions-Policy.',
      );
    } else {
      policies.add(b.responseHeadersPolicy);
    }
    if (b.viewerRequestSources.length === 0) {
      errors.push(
        `${at}: no viewer-request function_association. The viewer-request function is what ` +
          'redirects the `www.` host to the apex, and CloudFront associates a function PER ' +
          'BEHAVIOUR — an unassociated path serves the whole site at a second host, which is the ' +
          'duplicate-content split the function exists to close.',
      );
    }
    for (const source of b.viewerRequestSources) viewerRequestSources.add(source);
  }

  if (policies.size > 1) {
    errors.push(
      `the behaviours name ${policies.size} different response-headers policies ` +
        `(${[...policies].sort().join(', ')}). One of them is the security policy and the rest are ` +
        'whatever a copy-paste reached for; a per-path CSP difference is not something a reader of ' +
        'this file can see.',
    );
  }
  for (const ref of policies) {
    const label = ref.match(/^aws_cloudfront_response_headers_policy\.([A-Za-z0-9_-]+)\.id$/)?.[1];
    if (label === undefined) {
      errors.push(
        `response_headers_policy_id ${JSON.stringify(ref)} does not reference a policy this module ` +
          'declares, so what it carries could not be read.',
      );
      continue;
    }
    const policy = headerPolicies.get(label);
    if (policy === undefined) {
      errors.push(
        `the behaviours are served under aws_cloudfront_response_headers_policy.${label}, which this ` +
          'module does not declare.',
      );
    } else if (!policy.csp || !policy.permissionsPolicy) {
      errors.push(
        `aws_cloudfront_response_headers_policy.${label} carries ` +
          `${policy.csp ? '' : 'no content_security_policy'}${!policy.csp && !policy.permissionsPolicy ? ' and ' : ''}` +
          `${policy.permissionsPolicy ? '' : 'no Permissions-Policy header'}. Every behaviour on the ` +
          'distribution points at it, so the whole site loses that header at once.',
      );
    } else {
      ok.push(
        `all ${behaviours.length} cache behaviours: CSP + Permissions-Policy via ${label}`,
      );
    }
  }

  if (viewerRequestSources.size > 1) {
    errors.push(
      `the behaviours associate ${viewerRequestSources.size} different viewer-request functions ` +
        `(${[...viewerRequestSources].sort().join(', ')}). Every path on this distribution runs the ` +
        'same edge function or the host consolidation is per-path, which nothing states.',
    );
  } else if (viewerRequestSources.size === 1) {
    ok.push(
      `all ${behaviours.length} cache behaviours: viewer-request function from ${[...viewerRequestSources][0]}`,
    );
  }
  if (originsMissingOac.length === 0 && insecureOrigins.length === 0) {
    ok.push(`all ${originIds.length} distribution origins: OAC-signed, https-only`);
  }
}

export function main() {
  const { errors, ok } = compareSources(
    terraformDirs(INFRA_DIR),
    parseStackMatrix(readFileSync(TERRAFORM_WORKFLOW, 'utf-8')),
    parseDependabotTerraform(readFileSync(DEPENDABOT_FILE, 'utf-8')),
    parseModuleFunctions(readFileSync(MODULE_FILE, 'utf-8')),
    parseAlarms(readFileSync(ALARMS_FILE, 'utf-8')),
    parseDistribution(readFileSync(MODULE_FILE, 'utf-8')),
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
