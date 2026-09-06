#!/usr/bin/env node
// Guardrail: the distribution's `custom_error_response` set, and the handler
// behaviour that is the reason it is the size it is.
//
// `custom_error_response` is DISTRIBUTION-wide — CloudFront models it per
// distribution rather than per cache behaviour — so one block rewrites the body
// of every origin's error at once. That is what made ten `/share/*` paths soft
// 404s (§ 1022), and it is why the set has to be argued for rather than grown.
//
// Two mappings existed. § 1036 removed the reason for one of them: all five
// share Lambdas now return the SPA shell AT 404 themselves, with the `noindex`
// in it, so the 404 mapping was replacing an honest body with an identical one
// minus the tag the whole crawler fix was about. Dropping it is what puts the
// tag on the wire (§ 1084). But "dropped" and "dropped for a reason that still
// holds" are different states, and only the second is safe: if a handler ever
// stops returning the shell, its bare `<p>This link isn't available.</p>` goes
// straight to the reader on ten paths, and nothing in `infra/` can see that.
//
// So the two halves are checked together:
//
//   1. No `custom_error_response` for 404. The handlers own that status now.
//   2. The 403 mapping stays, and stays at 200. That is the SPA deep-link path
//      — the site bucket grants s3:GetObject with no s3:ListBucket, so every
//      dynamic client route arrives as a missing key, i.e. 403 AccessDenied.
//      Answering it 403 breaks the whole app, which is the opposite failure to
//      the one § 1022 fixed and is why the two blocks were never symmetric.
//   3. Every share Lambda handler answers its own 404 with `notFoundShell`.
//      This is claim 1's premise, read from the source rather than assumed. The
//      handler set is DERIVED from the `apps/web/lambda/share-*` directory
//      listing, so a sixth share Lambda is covered without anyone remembering.
//
// Sibling of check_infra_coverage.mjs's status-laundering rule, which asks a
// different question about the same blocks: that one refuses a 4xx/5xx mapped
// to a 2xx, this one refuses the 404 block existing at all. Neither subsumes
// the other — a 404 -> 404 mapping launders no status and is exactly what was
// removed.
//
// Offline: no AWS credentials, no `terraform init`, stdlib only.
//
// Run: `node scripts/check_infra_error_responses.mjs`
// CI:  the `infra-guards` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_infra_error_responses.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { hclResources, nestedBlocks, stripComments } from './hcl_lex.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const MODULE_FILE = join(REPO_ROOT, 'infra', 'modules', 'web-stack', 'main.tf');
export const LAMBDA_DIR = join(REPO_ROOT, 'apps', 'web', 'lambda');

/// The one mapping that is allowed to exist, and what it must answer with.
/// Written as a pair rather than a status list because the whole point is that
/// 403 and 404 are NOT symmetric: 403 must be laundered to 200 or the SPA is
/// broken, 404 must not be touched at all or the handlers' `noindex` is thrown
/// away.
/// The page is `/200.html`, adapter-static's SPA fallback, and not
/// `/index.html`: since decisions § 1268 that filename holds the prerendered
/// landing page, whose relative asset URLs and route-"/" hydration payload
/// make it unusable as a deep-link body.
export const REQUIRED_MAPPING = { errorCode: '403', responseCode: '200', page: '/200.html' };

/// Statuses no `custom_error_response` may claim, with the reason each is
/// owned elsewhere. An entry nothing violates is the normal state; an entry
/// that stops being true is what this exists to catch.
export const FORBIDDEN_ERROR_CODES = new Map([
  [
    '404',
    'the five share Lambdas return the SPA shell at 404 themselves (§ 1036), so this mapping ' +
      'only replaces their body with an identical one from S3 — minus the `noindex` that lives ' +
      'in the Lambda body and nowhere else. It also answers /api/coach*\'s JSON 404 with an HTML ' +
      'shell. S3 never produces a 404 on this distribution anyway: the bucket policy grants ' +
      's3:GetObject with no s3:ListBucket, so a missing key is 403',
  ],
]);

/** @param {string} body @param {string} key */
function attr(body, key) {
  return body.match(new RegExp(`^\\s*${key}\\s*=\\s*(.+?)\\s*$`, 'm'))?.[1]?.replace(/^"|"$/g, '') ?? null;
}

/**
 * Every `custom_error_response` block on the module's distribution.
 * Null when no `aws_cloudfront_distribution` could be read at all, which the
 * caller reports rather than treating as "nothing to check" — a parser that
 * stops matching otherwise passes vacuously, which is a source-reading guard's
 * failure mode instead of a false negative.
 *
 * @param {string} raw
 * @returns {{ errorCode: string | null, responseCode: string | null, page: string | null }[] | null}
 */
export function parseErrorResponses(raw) {
  const src = stripComments(raw);
  const distributions = hclResources(src, 'aws_cloudfront_distribution');
  if (distributions.length === 0) return null;
  /** @type {{ errorCode: string | null, responseCode: string | null, page: string | null }[]} */
  const out = [];
  for (const dist of distributions) {
    for (const block of nestedBlocks(dist.body, /custom_error_response\s*\{/g)) {
      out.push({
        errorCode: attr(block.body, 'error_code'),
        responseCode: attr(block.body, 'response_code'),
        page: attr(block.body, 'response_page_path'),
      });
    }
  }
  return out;
}

/**
 * The share Lambda handlers, derived from the directory listing.
 *
 * @param {string} dir
 * @returns {{ name: string, source: string }[]}
 */
export function readShareHandlers(dir) {
  /** @type {{ name: string, source: string }[]} */
  const out = [];
  for (const name of readdirSync(dir).sort()) {
    if (!name.startsWith('share-')) continue;
    let source;
    try {
      source = readFileSync(join(dir, name, 'src', 'index.ts'), 'utf-8');
    } catch {
      continue;
    }
    out.push({ name, source });
  }
  return out;
}

/// How far back from a `notFoundShell(` call to look for the status that
/// carries it. Both live shapes — an object literal with `statusCode: 404` and
/// a `html(404, notFoundShell(...))` helper call — put the two within a few
/// lines of each other.
const STATUS_WINDOW = 400;

/**
 * Does this handler answer a 404 with the SPA shell?
 *
 * @param {string} source
 * @returns {boolean}
 */
export function answersNotFoundWithShell(source) {
  for (const m of source.matchAll(/notFoundShell\s*\(/g)) {
    const before = source.slice(Math.max(0, m.index - STATUS_WINDOW), m.index);
    if (/statusCode\s*:\s*404/.test(before) || /\(\s*404\s*,\s*$/.test(before)) return true;
  }
  return false;
}

/**
 * @param {ReturnType<typeof parseErrorResponses>} responses
 * @param {ReturnType<typeof readShareHandlers>} handlers
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkErrorResponses(responses, handlers) {
  /** @type {string[]} */
  const errors = [];
  /** @type {string[]} */
  const ok = [];

  if (responses === null) {
    errors.push(
      'no `aws_cloudfront_distribution` found in the web-stack module — this guard read nothing, ' +
        'so its claims below would have passed vacuously.',
    );
    return { errors, ok };
  }

  for (const r of responses) {
    const reason = r.errorCode === null ? undefined : FORBIDDEN_ERROR_CODES.get(r.errorCode);
    if (reason !== undefined) {
      errors.push(
        `custom_error_response error_code = ${r.errorCode} is back. It must not exist: ${reason}. ` +
          'decisions § 1084.',
      );
    }
  }

  const required = responses.filter((r) => r.errorCode === REQUIRED_MAPPING.errorCode);
  if (required.length !== 1) {
    errors.push(
      `expected exactly one custom_error_response for ${REQUIRED_MAPPING.errorCode}, found ` +
        `${required.length}. That block is the SPA deep-link path — every dynamic client route ` +
        'is a missing S3 key, and the bucket policy makes a missing key a 403 — so without it ' +
        'the whole app answers AccessDenied. decisions § 1022.',
    );
  } else {
    const r = required[0];
    if (r.responseCode !== REQUIRED_MAPPING.responseCode || r.page !== REQUIRED_MAPPING.page) {
      errors.push(
        `custom_error_response ${r.errorCode} answers ${r.responseCode} with ${r.page}; it must ` +
          `answer ${REQUIRED_MAPPING.responseCode} with ${REQUIRED_MAPPING.page}. This is the one ` +
          'mapping whose whole job is to launder a status: a real 403 reaches a reader as the SPA. ' +
          'decisions § 1022.',
      );
    } else {
      ok.push(
        `custom_error_response ${r.errorCode} -> ${r.responseCode} ${r.page} (the SPA deep-link path)`,
      );
    }
  }

  const forbidden = [...FORBIDDEN_ERROR_CODES.keys()].sort();
  ok.push(`no custom_error_response for ${forbidden.join(', ')} (${responses.length} block(s) read)`);

  if (handlers.length === 0) {
    errors.push(
      `no share-* handler found under ${LAMBDA_DIR} — claim 1's premise was read from nothing.`,
    );
  } else {
    const bare = handlers.filter((h) => !answersNotFoundWithShell(h.source)).map((h) => h.name);
    if (bare.length > 0) {
      errors.push(
        `${bare.join(', ')} does not answer its own 404 with notFoundShell. That is the premise ` +
          'under dropping the distribution\'s 404 mapping: with the mapping gone, whatever body ' +
          'the handler returns is what the reader gets, and the pre-§ 1036 body was one unstyled ' +
          'English sentence. Either restore the shell in the handler or state why the mapping is ' +
          'needed again. decisions §§ 1036, 1084.',
      );
    } else {
      ok.push(`all ${handlers.length} share Lambda handlers answer 404 with the SPA shell`);
    }
  }

  return { errors, ok };
}

export function main() {
  const { errors, ok } = checkErrorResponses(
    parseErrorResponses(readFileSync(MODULE_FILE, 'utf-8')),
    readShareHandlers(LAMBDA_DIR),
  );

  for (const line of ok) console.log(`[OK] ${line}`);
  for (const line of errors) console.error(`[FAIL] ${line}`);

  if (errors.length > 0) {
    console.error(
      `\n${errors.length} error-response finding(s).\n` +
        `  module:   ${MODULE_FILE}\n` +
        `  handlers: ${LAMBDA_DIR}\n`,
    );
    return 1;
  }
  console.log(`\n${ok.length} error-response property/properties hold.`);
  return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());
