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
//      .github/dependabot.yml". A stack absent from the matrix gets no
//      `validate` of its own; one absent from dependabot never hears about a
//      provider CVE. Neither absence shows up as a red check — the workflow
//      simply has one fewer green row than it could have, which is invisible
//      next to the twenty it does have.
//
//      infra/modules/web-stack is the one directory that cannot be validated
//      on its own: it takes an `aws.us_east_1` aliased provider from its
//      caller, so a standalone `terraform validate` fails with "Provider
//      configuration not present" (measured, not assumed, and still true under
//      `configuration_aliases`). It is exempt here WITH that reason, and the
//      exemption fails if it ever stops being needed.
//
//      The exemption is from `validate` and from NOTHING ELSE. `fmt` has no
//      such excuse — formatting a module needs no provider — and it was
//      nonetheless skipped for a year, because the fmt step lived inside the
//      matrix job with a per-stack `working-directory` and `terraform fmt`
//      without `-recursive` reads one directory. Measured: drift added to
//      infra/modules/web-stack left all five per-stack steps exiting 0.
//      So the fmt invocations are read out of the workflow as SCOPES — a
//      directory plus whether `-recursive` extends it over the subtree — and
//      every Terraform directory must fall inside one, exempt or not.
//      decisions § 1111.
//
//      That whole half is scoped to `infra/`, which is also the answer it
//      assumes: the walk starts there, so a `.tf` file in some other tree is
//      not reported as uncovered, it is not seen. Nothing else would see it
//      either — ci.yml's `changes` job gates the `terraform` call on an
//      `infra/`-shaped path filter inherited from the old workflow trigger, so
//      such a stack is format-checked, validated, Trivy-scanned and TRIGGERED
//      by nothing, and reads as covered because nothing looks. A second sweep
//      therefore runs from the repo ROOT and fails on any Terraform directory
//      outside `infra/`, which turns "a stack somewhere else" into a red check
//      and leaves the path filter honest at `infra/` rather than widened to a
//      tree that does not exist. Today there is none (measured), so the sweep's
//      verdict is an absence — and an absence from a walk that never started is
//      worth nothing, which is why the sweep also reports whether it saw
//      `infra/` at the top level.
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
//      rather than per behaviour, so the SPA `403 → /index.html at 200`
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
//   5. WAF scope-down normalisation. The three rate-based rules are the only
//      thing bounding spend on the only three paths that cost money or engine
//      CPU to serve, and each is scoped down by a STARTS_WITH match on
//      `uri_path` — a field WAF does not decode, while CloudFront's behaviour
//      matching normalises independently. A scope-down with no URL_DECODE
//      transformation lets an encoded spelling reach the Lambda with the
//      per-IP cap unapplied, and looks identical in the console to one that
//      does not (decisions § 1023). A fourth rule copy-pasted from the first
//      three inherits the gap silently, which is what this claim is for.
//
//   6. Engine-URL symmetry. The module takes three routing-engine URLs, each a
//      string input defaulting to "" (the value that means "no engine, degrade
//      gracefully"). An env root that cannot SET one cannot rehearse a prod
//      change that involves it — which is what a preview environment is for —
//      and the omission is invisible: the module receives "" either way, the
//      plan is identical, and nothing reads as missing. `graph_cycle_url` was
//      in exactly that state (decisions § 1024): declared and wired in
//      envs/prod, declared nowhere in envs/preview, with no recorded reason
//      while its two siblings carried one. The engine set is DERIVED from the
//      module (a `_url` string input whose default is "") rather than listed,
//      so a fourth engine is covered the day it is added. The three deliberate
//      prod-only knobs measured alongside it — the reserved-concurrency caps —
//      are literals in preview WITH a stated reason and are not this shape.
//
// Offline by design: a directory listing and six files. No AWS credentials,
// no `terraform init`.
//
// Run: `node scripts/check_infra_coverage.mjs`
// CI:  the `infra-guards` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_infra_coverage.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseSteps, runBody } from './check_ci_diagnostics.mjs';
import {
  blockEnd,
  hclResources,
  nestedBlock,
  nestedBlocks,
  stripComments,
} from './hcl_lex.mjs';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

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
export const WAF_FILE =
  process.env.INFRA_COVERAGE_WAF ??
  join(REPO_ROOT, 'infra/modules/web-stack/waf.tf');
export const MODULE_VARS_FILE =
  process.env.INFRA_COVERAGE_MODULE_VARS ??
  join(REPO_ROOT, 'infra/modules/web-stack/variables.tf');
/// Each env root, as `{ env, main, variables }` source text. Overridable as a
/// comma-separated list of env NAMES rooted under a directory, so the whole
/// script can be pointed at mutated copies.
export const ENV_ROOT_DIR =
  process.env.INFRA_COVERAGE_ENV_DIR ?? join(REPO_ROOT, 'infra/envs');
export const ENV_NAMES = (process.env.INFRA_COVERAGE_ENVS ?? 'prod,preview').split(',');

/// The transformation every `uri_path` scope-down must carry, and the one it
/// must not. See claim 5 in the header.
export const REQUIRED_URI_TRANSFORM = 'URL_DECODE';
export const FORBIDDEN_URI_TRANSFORM = 'LOWERCASE';

/// Directories `terraform validate` cannot be run against on their own, and
/// why. An entry that stops being needed fails as loudly as a missing one.
/// Exempt from VALIDATE only — every directory here is still fmt-checked and
/// Trivy-scanned, both of which walk the tree rather than the matrix.
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

/// Trees the repo-root sweep below does not descend into. Everything here is
/// either a dependency tree or build output — a `.tf` inside one is not a stack
/// anyone deploys, and `node_modules` alone is large enough to dominate the
/// walk's cost.
export const STRAY_SCAN_SKIP = new Set([
  'node_modules',
  'build',
  'dist',
  'target',
  'vendor',
  'coverage',
]);

/// Every directory ANYWHERE in the repo holding `.tf` files, except under the
/// top-level `infra/`.
///
/// `terraformDirs` walks `infra/` and therefore can only ever report on
/// directories already inside the one tree CI reads: `ci.yml`'s `changes` job
/// gates the `terraform` call on an `infra/`-shaped path filter, and the fmt
/// scopes, the stack matrix and the dependabot entries are all paths under it.
/// A `.tf` file outside that tree is format-checked, validated, Trivy-scanned
/// and triggered by nothing at all, and reads as covered precisely because
/// nothing looks — the same shape as the per-stack `fmt` scope § 1111 closed,
/// one level up.
///
/// `rooted` is the vacuity guard: this sweep's whole verdict is an absence, and
/// an absence proves nothing if the walk never started. The top-level listing
/// naming `infra` is what says it ran against the repo root rather than against
/// an unreadable path.
/**
 * @param {string} root absolute path to the repo root
 * @param {(dir: string) => string[]} [list] injectable for the tests
 * @returns {{ dirs: string[], rooted: boolean }}
 */
export function scanStrayTerraform(root, list = (d) => readdirSync(d)) {
  /** @type {string[]} */
  const out = [];
  let rooted = false;
  /** @param {string} abs @param {string} rel */
  const walk = (abs, rel) => {
    /** @type {string[]} */
    let entries;
    try {
      entries = list(abs);
    } catch {
      return;
    }
    if (rel === '') rooted = entries.includes('infra');
    if (entries.some((e) => e.endsWith('.tf'))) out.push(rel === '' ? '.' : rel);
    for (const entry of entries) {
      if (entry.startsWith('.')) continue;
      if (rel === '' && entry === 'infra') continue;
      if (STRAY_SCAN_SKIP.has(entry)) continue;
      walk(join(abs, entry), rel === '' ? entry : `${rel}/${entry}`);
    }
  };
  walk(root, '');
  return { dirs: out.sort(), rooted };
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

/// Every `terraform fmt` invocation in the workflow, as the tree it reads.
///
/// `dir` is the directory the command resolves against: its own path argument
/// if it has one, else the step's `working-directory`, else the repo root. A
/// `${{ matrix.stack }}` working-directory expands to one scope per matrix
/// entry, because that is what the job does. `recursive` says whether the scope
/// reaches subdirectories — without it `terraform fmt` reads exactly one
/// directory's .tf files, which is how a module inside the tree went unchecked.
/**
 * @param {string} src
 * @param {readonly string[]} matrix
 * @returns {{ dir: string, recursive: boolean }[]}
 */
export function parseFmtScopes(src, matrix) {
  /** @type {{ dir: string, recursive: boolean }[]} */
  const scopes = [];
  for (const step of parseSteps(src)) {
    if (!step.hasRun) continue;
    for (const line of runBody(step).split('\n')) {
      if (/^\s*#/.test(line)) continue;
      const cmd = line.match(/\bterraform\s+fmt\b(.*)$/);
      if (!cmd) continue;
      const recursive = /(^|\s)-recursive(\s|$)/.test(cmd[1]);
      const positional = cmd[1]
        .split(/\s+/)
        .filter((t) => t !== '' && !t.startsWith('-'));
      /** @type {string[]} */
      const dirs =
        positional.length > 0
          ? positional
          : (() => {
              const wd = step.body.match(/^\s*working-directory:\s*(.+?)\s*$/m)?.[1];
              if (wd === undefined) return ['.'];
              if (/\$\{\{\s*matrix\.stack\s*\}\}/.test(wd)) return [...matrix];
              return [wd.replace(/^['"]|['"]$/g, '')];
            })();
      for (const dir of dirs) {
        scopes.push({ dir: dir.replace(/^\.\//, '').replace(/\/+$/, ''), recursive });
      }
    }
  }
  return scopes;
}

/// Whether a Terraform directory falls inside some fmt scope. A non-recursive
/// scope covers only itself; the repo root covers everything only when it is
/// recursive.
/**
 * @param {string} dir
 * @param {readonly { dir: string, recursive: boolean }[]} scopes
 * @returns {boolean}
 */
export function fmtCovers(dir, scopes) {
  return scopes.some((scope) => {
    if (scope.dir === dir) return true;
    if (!scope.recursive) return false;
    return scope.dir === '.' || dir.startsWith(`${scope.dir}/`);
  });
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

/**
 * @typedef {{ rule: string, searchString: string | null, field: string | null,
 *             positional: string | null, transforms: string[] }} WafScopeDown
 */

/// Every rate-based rule's scope-down byte match, with the text transformations
/// it applies. A rule whose scope-down could not be read is returned with a
/// null search string rather than dropped — an unreadable rule is not a
/// passing one.
/**
 * @param {string} raw the waf.tf source
 * @returns {WafScopeDown[]}
 */
export function parseWafScopeDowns(raw) {
  const src = stripComments(raw);
  /** @type {WafScopeDown[]} */
  const out = [];
  for (const acl of hclResources(src, 'aws_wafv2_web_acl')) {
    for (const { body } of nestedBlocks(acl.body, /(?:^|\n)\s*rule\s*\{/)) {
      const rule = unquote(attr(body, 'name')) ?? '(unnamed)';
      const rateBased = nestedBlock(body, /rate_based_statement\s*\{/);
      if (rateBased === null) continue;
      const scopeDown = nestedBlock(rateBased, /scope_down_statement\s*\{/);
      const byteMatch =
        scopeDown === null ? null : nestedBlock(scopeDown, /byte_match_statement\s*\{/);
      if (byteMatch === null) {
        out.push({ rule, searchString: null, field: null, positional: null, transforms: [] });
        continue;
      }
      const fieldBlock = nestedBlock(byteMatch, /field_to_match\s*\{/) ?? '';
      const field = fieldBlock.match(/(\w+)\s*\{\s*\}/)?.[1] ?? null;
      out.push({
        rule,
        searchString: unquote(attr(byteMatch, 'search_string')),
        field,
        positional: unquote(attr(byteMatch, 'positional_constraint')),
        transforms: nestedBlocks(byteMatch, /text_transformation\s*\{/)
          .map(({ body: t }) => unquote(attr(t, 'type')) ?? '(unreadable)'),
      });
    }
  }
  return out;
}

/**
 * @typedef {{ name: string, type: string | null, dflt: string | null }} ModuleVar
 * @typedef {{ env: string, declared: Set<string>, wired: Map<string, string> }} EnvRoot
 */

/// Every `variable "…" { … }` in a Terraform variables file, with its declared
/// type and default as written.
/**
 * @param {string} raw
 * @returns {ModuleVar[]}
 */
export function parseVariables(raw) {
  const src = stripComments(raw);
  /** @type {ModuleVar[]} */
  const out = [];
  const re = /(?:^|\n)\s*variable\s+"([A-Za-z0-9_-]+)"\s*\{/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const open = m.index + m[0].length - 1;
    const close = blockEnd(src, open);
    if (close < 0) continue;
    const body = src.slice(open + 1, close);
    out.push({ name: m[1], type: attr(body, 'type'), dflt: attr(body, 'default') });
    re.lastIndex = close;
  }
  return out;
}

/// The routing-engine URL inputs, derived rather than listed: a `_url` string
/// input whose default is the empty string. That default IS the semantics —
/// "" means no engine and a graceful degrade — which is what separates the
/// three engines from `public_supabase_url` (no default, required) and
/// `public_site_url` (a real default, and env identity rather than a knob).
/**
 * @param {ModuleVar[] } vars
 * @returns {string[]}
 */
export function engineUrlInputs(vars) {
  return vars
    .filter((v) => v.name.endsWith('_url') && v.type === 'string' && v.dflt === '""')
    .map((v) => v.name);
}

/// One env root: the variables it declares, and what its `module "web"` block
/// wires each module input from.
/**
 * @param {string} env
 * @param {string} mainSrc
 * @param {string} variablesSrc
 * @returns {EnvRoot}
 */
export function parseEnvRoot(env, mainSrc, variablesSrc) {
  const src = stripComments(mainSrc);
  /** @type {Map<string, string>} */
  const wired = new Map();
  const re = /(?:^|\n)\s*module\s+"[A-Za-z0-9_-]+"\s*\{/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    const open = m.index + m[0].length - 1;
    const close = blockEnd(src, open);
    if (close < 0) continue;
    for (const a of src
      .slice(open + 1, close)
      .matchAll(/^\s*([a-z0-9_]+)\s*=\s*(.+?)\s*$/gm))
      if (!wired.has(a[1])) wired.set(a[1], a[2]);
    re.lastIndex = close;
  }
  return {
    env,
    declared: new Set(parseVariables(variablesSrc).map((v) => v.name)),
    wired,
  };
}

// ────────────────────────────── comparison ──────────────────────────────

/**
 * @param {string[]} dirs
 * @param {string[]} matrix
 * @param {{ dir: string, recursive: boolean }[]} fmtScopes
 * @param {string[]} dependabot
 * @param {string[]} functions
 * @param {Alarm[]} alarms
 * @param {Distribution} distribution
 * @param {WafScopeDown[]} wafScopeDowns
 * @param {ModuleVar[]} moduleVars
 * @param {EnvRoot[]} envRoots
 * @param {{ dirs: string[], rooted: boolean }} strays
 * @returns {{ errors: string[], ok: string[] }}
 */
export function compareSources(
  dirs,
  matrix,
  fmtScopes,
  dependabot,
  functions,
  alarms,
  distribution,
  wafScopeDowns,
  moduleVars,
  envRoots,
  strays,
) {
  /** @type {string[]} */
  const errors = [];
  /** @type {string[]} */
  const ok = [];

  if (dirs.length === 0) {
    errors.push(
      'no Terraform directory was found under infra/ — the stack-coverage half checked nothing.',
    );
  }
  if (!strays.rooted) {
    errors.push(
      'the repo-root sweep for Terraform outside infra/ did not find infra/ at the top level, so ' +
        'it was not reading the repo root. Its verdict is an absence and an absence proves nothing ' +
        'from a walk that never started.',
    );
  } else if (strays.dirs.length === 0) {
    ok.push('no Terraform outside infra/, which is the only tree any CI job reads');
  }
  for (const dir of strays.dirs) {
    errors.push(
      `${dir} holds Terraform outside infra/, where no CI job reads it: the \`terraform\` call in ` +
        'ci.yml is gated on an `infra/`-shaped path filter, and the fmt scopes, the stack matrix ' +
        'and the dependabot entries are all paths under that tree — so this directory is ' +
        'format-checked, validated, Trivy-scanned and triggered by nothing. Move it under infra/, ' +
        'or widen the `infra` filter in ci.yml\'s `changes` job and cover it the way every stack ' +
        'above is covered.',
    );
  }
  if (matrix.length === 0) {
    errors.push(
      "could not read the `stack:` matrix out of the terraform workflow — the matrix moved, and " +
        'until this parses again an unvalidated stack reads as covered.',
    );
  }
  if (fmtScopes.length === 0) {
    errors.push(
      'no `terraform fmt` invocation was read out of the terraform workflow, so every directory ' +
        'below would report as format-checked by nothing this guard can see.',
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
      ok.push(`${dir}: validate + Trivy in CI`);
    } else if (exemption !== undefined) {
      usedExemptions.add(dir);
      ok.push(`${dir}: exempt from validate, still fmt + Trivy (${exemption.split(';')[0]})`);
    } else {
      errors.push(
        `${dir} holds Terraform that no CI job validates. Add it to the \`stack:\` matrix in ` +
          '.github/workflows/terraform.yml, or to VALIDATE_EXEMPT in this guard with the reason ' +
          'validate cannot run against it.',
      );
    }

    if (fmtScopes.length > 0 && !fmtCovers(dir, fmtScopes)) {
      errors.push(
        `${dir} holds Terraform that no \`terraform fmt\` invocation in the workflow reads. A ` +
          'per-stack step scoped by `working-directory` reads that one directory only, so drift ' +
          'here would never turn a check red. Widen the recursive pass, or add the directory to ' +
          'it. VALIDATE_EXEMPT exempts a directory from `validate` and from nothing else.',
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
        "on this distribution is invisible — CloudFront's per-distribution 4xx → SPA-shell " +
        'fallback replaces the body with the shell (and, for a 403, the status with a 200) — so ' +
        'the alarm is the only signal it has.',
    );
  }

  distributionCoverage(distribution, errors, ok);
  wafCoverage(wafScopeDowns, errors, ok);
  engineUrlCoverage(engineUrlInputs(moduleVars), envRoots, errors, ok);

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

/// The fifth: WAF does not decode `uri_path` and CloudFront's behaviour
/// matching normalises independently, so a scope-down without a URL_DECODE
/// transformation lets an encoded spelling reach the Lambda uncapped.
/**
 * @param {WafScopeDown[]} wafScopeDowns
 * @param {string[]} errors
 * @param {string[]} ok
 */
function wafCoverage(wafScopeDowns, errors, ok) {
  if (wafScopeDowns.length === 0) {
    errors.push(
      'no rate-based rule with a scope-down was read from waf.tf. The three of them are the only ' +
        'thing bounding spend on /api/coach, /api/routes/generate and /api/routes/osrm, so a count ' +
        'of zero means this scan stopped matching rather than that the rules are gone.',
    );
  }
  for (const { rule, searchString, field, positional, transforms } of wafScopeDowns) {
    if (searchString === null || field === null) {
      errors.push(
        `rate-based rule ${rule} has no readable byte_match scope-down. Without one the rate ` +
          'counter applies to EVERY request on the distribution, static assets included — the rule ' +
          'stops being a backstop and becomes an outage.',
      );
      continue;
    }
    if (field !== 'uri_path') {
      ok.push(`WAF ${rule}: scoped on ${field}, not uri_path — claim 5 does not apply`);
      continue;
    }
    if (transforms.includes(FORBIDDEN_URI_TRANSFORM)) {
      errors.push(
        `WAF ${rule} applies ${FORBIDDEN_URI_TRANSFORM} to uri_path. CloudFront path patterns are ` +
          'case-sensitive, so a differently-cased spelling does not reach the Lambda at all and ' +
          'folding case only rate-limits requests the edge already 404s.',
      );
    }
    if (!transforms.includes(REQUIRED_URI_TRANSFORM)) {
      errors.push(
        `WAF ${rule} matches uri_path ${positional} ${JSON.stringify(searchString)} with only ` +
          `[${transforms.join(', ')}]. WAF does not decode uri_path and CloudFront's behaviour ` +
          'matching normalises independently, so an encoded spelling that CloudFront resolves to ' +
          `the behaviour reaches the Lambda with the per-IP cap unapplied. Add a ` +
          `${REQUIRED_URI_TRANSFORM} transformation beside the NONE — on a search string with no ` +
          '`%` in it that can only widen the match, never narrow it. decisions § 1023.',
      );
      continue;
    }
    ok.push(`WAF ${rule}: uri_path ${positional} ${JSON.stringify(searchString)}, URL-decoded`);
  }
}

/// The sixth: every routing-engine URL the module takes is settable from every
/// env root. An env that cannot set one cannot rehearse a prod change
/// involving it, and the omission is invisible — the module receives "" either
/// way and the plan is identical.
/**
 * @param {string[]} engines
 * @param {EnvRoot[]} roots
 * @param {string[]} errors
 * @param {string[]} ok
 */
function engineUrlCoverage(engines, roots, errors, ok) {
  if (engines.length === 0) {
    errors.push(
      'no engine URL input was read from the web-stack variables file. The module takes three ' +
        '(osrm, graphhopper, graph_cycle); a count of zero means this reader stopped matching ' +
        'rather than that the engines are gone.',
    );
    return;
  }
  if (roots.length < 2) {
    errors.push(
      `only ${roots.length} env root(s) were read. Symmetry between them is the whole claim, and ` +
        'one root is symmetric with itself.',
    );
    return;
  }
  for (const root of roots) {
    if (root.wired.size === 0) {
      errors.push(
        `envs/${root.env}: no \`module "web"\` argument was read, so nothing about its engine URLs ` +
          'was checked.',
      );
    }
  }
  for (const engine of engines) {
    /** @type {string[]} */
    const gaps = [];
    for (const root of roots) {
      if (!root.declared.has(engine)) gaps.push(`envs/${root.env} declares no var.${engine}`);
      else if (!root.wired.has(engine))
        gaps.push(`envs/${root.env} declares var.${engine} and does not pass it to the module`);
    }
    if (gaps.length === 0) {
      ok.push(`${engine}: settable from all ${roots.length} env roots`);
      continue;
    }
    errors.push(
      `${engine} is a routing-engine URL the module takes, and ${gaps.join('; ')}. An environment ` +
        'that cannot be configured the way prod can cannot rehearse a prod change, and the gap is ' +
        'invisible: the module gets the same "" it would have got, so the plan is identical and ' +
        'nothing reads as missing. Three lines — a variable, a wire, a description. ' +
        'decisions § 1024.',
    );
  }
}

export function main() {
  const workflowSrc = readFileSync(TERRAFORM_WORKFLOW, 'utf-8');
  const matrix = parseStackMatrix(workflowSrc);
  const { errors, ok } = compareSources(
    terraformDirs(INFRA_DIR),
    matrix,
    parseFmtScopes(workflowSrc, matrix),
    parseDependabotTerraform(readFileSync(DEPENDABOT_FILE, 'utf-8')),
    parseModuleFunctions(readFileSync(MODULE_FILE, 'utf-8')),
    parseAlarms(readFileSync(ALARMS_FILE, 'utf-8')),
    parseDistribution(readFileSync(MODULE_FILE, 'utf-8')),
    parseWafScopeDowns(readFileSync(WAF_FILE, 'utf-8')),
    parseVariables(readFileSync(MODULE_VARS_FILE, 'utf-8')),
    ENV_NAMES.map((env) =>
      parseEnvRoot(
        env,
        readFileSync(join(ENV_ROOT_DIR, env, 'main.tf'), 'utf-8'),
        readFileSync(join(ENV_ROOT_DIR, env, 'variables.tf'), 'utf-8'),
      ),
    ),
    scanStrayTerraform(REPO_ROOT),
  );

  for (const line of ok) console.log(`[OK] ${line}`);
  for (const line of errors) console.error(`[FAIL] ${line}`);

  if (errors.length > 0) {
    console.error(`\n${errors.length} infra coverage gap(s).`);
    return 1;
  }
  console.log(`\n${ok.length} infra coverage claim(s) hold.`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
