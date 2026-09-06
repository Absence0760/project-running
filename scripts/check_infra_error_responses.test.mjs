import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';

import {
  FORBIDDEN_ERROR_CODES,
  LAMBDA_DIR,
  MODULE_FILE,
  REQUIRED_MAPPING,
  answersNotFoundWithShell,
  checkErrorResponses,
  parseErrorResponses,
  readShareHandlers,
} from './check_infra_error_responses.mjs';

// ─────────────────────────────── fixtures ───────────────────────────────

/** @param {string} blocks */
const distribution = (blocks) => `
resource "aws_cloudfront_distribution" "this" {
  enabled = true
  # A comment with an unbalanced { brace and a "quoted 404" in it.
  default_cache_behavior {
    target_origin_id = "site"
  }
${blocks}
}
`;

/// The shell filename is read off the contract rather than spelled here: it
/// moved from /index.html to /200.html when the landing page was prerendered
/// onto index.html (decisions § 1268), and a fixture that keeps the old
/// spelling stops exercising the shape it was written for. The one test that
/// DOES spell a filename is the page-mismatch case below, which must name a
/// wrong one to be about anything.
const SHELL = REQUIRED_MAPPING.page;

const SPA_403 = `
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "${SHELL}"
  }
`;

const SHELL_404_OBJECT = `
if (!lookup.run) {
  return {
    statusCode: 404,
    headers: { 'content-type': 'text/html; charset=utf-8' },
    body: notFoundShell(__SPA_SHELL_HTML__, 'Run not found'),
  };
}
`;

const SHELL_404_HELPER = `
if (!headTags) return html(404, notFoundShell(__SPA_SHELL_HTML__, 'Not found'));
`;

/** @param {string} source */
const handlers = (source) => [{ name: 'share-run', source }];

// ─────────────────────────────── the parser ───────────────────────────────

test('reads every custom_error_response on the distribution', () => {
  const parsed = parseErrorResponses(distribution(`${SPA_403}\n  custom_error_response {\n    error_code = 404\n    response_code = 404\n    response_page_path = "${SHELL}"\n  }`));
  assert.deepEqual(parsed, [
    { errorCode: '403', responseCode: '200', page: SHELL },
    { errorCode: '404', responseCode: '404', page: SHELL },
  ]);
});

test('a commented-out block is not a block', () => {
  // The module's own comments name the mapping repeatedly, including the one
  // that was removed. A guard that reads prose reports the absence as presence.
  const parsed = parseErrorResponses(
    distribution(`${SPA_403}\n  # custom_error_response {\n  #   error_code = 404\n  # }`),
  );
  assert.deepEqual(parsed, [{ errorCode: '403', responseCode: '200', page: SHELL }]);
});

test('a source with no distribution reads null, not an empty set', () => {
  assert.equal(parseErrorResponses('resource "aws_s3_bucket" "site" {}'), null);
});

// ─────────────────────────────── the claims ───────────────────────────────

test('the shipped tree passes', () => {
  const { errors } = checkErrorResponses(
    parseErrorResponses(readFileSync(MODULE_FILE, 'utf-8')),
    readShareHandlers(LAMBDA_DIR),
  );
  assert.deepEqual(errors, []);
});

test('the shipped tree is what the guard claims it read', () => {
  // Vacuity: every claim below is a filter over these two, so a parser that
  // stopped matching would pass all of them while checking nothing.
  const parsed = parseErrorResponses(readFileSync(MODULE_FILE, 'utf-8'));
  assert.ok(parsed !== null && parsed.length >= 1);
  assert.ok(readShareHandlers(LAMBDA_DIR).length >= 5);
});

test('a returning 404 mapping fails, and the message says why it is not needed', () => {
  const { errors } = checkErrorResponses(
    [
      { errorCode: '403', responseCode: '200', page: SHELL },
      { errorCode: '404', responseCode: '404', page: SHELL },
    ],
    handlers(SHELL_404_OBJECT),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /error_code = 404 is back/);
  assert.match(errors[0], /noindex/);
});

test('the 403 mapping may not be dropped', () => {
  const { errors } = checkErrorResponses([], handlers(SHELL_404_OBJECT));
  assert.equal(errors.length, 1);
  assert.match(errors[0], /found 0/);
});

test('the 403 mapping may not answer 403', () => {
  // The opposite failure to the one § 1022 fixed: an honest status here breaks
  // every dynamic client route.
  const { errors } = checkErrorResponses(
    [{ errorCode: '403', responseCode: '403', page: SHELL }],
    handlers(SHELL_404_OBJECT),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /answers 403/);
});

test('the 403 mapping may not point at the prerendered landing page', () => {
  // The regression decisions § 1268 makes possible: index.html is the landing
  // page now, whose relative asset URLs resolve under the deep link's own
  // directory. Serving it here loads nothing at all on /runs/<id>.
  const { errors } = checkErrorResponses(
    [{ errorCode: '403', responseCode: '200', page: '/index.html' }],
    handlers(SHELL_404_OBJECT),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /\/index\.html/);
});

test('a null parse is reported rather than passing every claim', () => {
  const { errors, ok } = checkErrorResponses(null, handlers(SHELL_404_OBJECT));
  assert.equal(ok.length, 0);
  assert.match(errors[0], /read nothing/);
});

// ────────────────────── the handler half of the premise ──────────────────────

test('both live 404-with-shell shapes are recognised', () => {
  assert.ok(answersNotFoundWithShell(SHELL_404_OBJECT));
  assert.ok(answersNotFoundWithShell(SHELL_404_HELPER));
});

test('a shell returned at 200 is not a 404 answer', () => {
  assert.equal(
    answersNotFoundWithShell("return html(200, notFoundShell(__SPA_SHELL_HTML__, 'x'));"),
    false,
  );
});

test('a handler that stops returning the shell fails, because the mapping is gone', () => {
  const { errors } = checkErrorResponses(
    [{ errorCode: '403', responseCode: '200', page: SHELL }],
    [
      { name: 'share-run', source: SHELL_404_OBJECT },
      { name: 'share-badge', source: "return { statusCode: 404, body: '<p>gone</p>' };" },
    ],
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /share-badge/);
  assert.match(errors[0], /unstyled English sentence/);
});

test('an empty handler set is reported, not read as clean', () => {
  const { errors } = checkErrorResponses(
    [{ errorCode: '403', responseCode: '200', page: SHELL }],
    [],
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /premise was read from nothing/);
});

test('every forbidden code carries its reason', () => {
  assert.ok(FORBIDDEN_ERROR_CODES.size > 0);
  for (const [code, reason] of FORBIDDEN_ERROR_CODES) {
    assert.match(code, /^[45]\d\d$/);
    assert.ok(reason.length > 40, `${code} needs a reason, not a label`);
  }
  assert.equal(
    FORBIDDEN_ERROR_CODES.has(REQUIRED_MAPPING.errorCode),
    false,
    'the required mapping cannot also be forbidden',
  );
});
