#!/usr/bin/env node
// Mutation-check the handler-envelope integration suite against the SERVED
// Edge Function tree.
//
// decisions.md 788 mutation-checks the Deno suite by neutering every module the
// TEST PROCESS imports. `_shared/handler_envelope.test.ts` imports none of
// them: it drives a separately-booted `supabase functions serve` host over
// HTTP, so that operator scores its cases as neither killed nor survived. They
// were the only Edge Function assertions in the repo with no measurement
// behind them (decisions § 815).
//
// The operator here mutates the tree the HOST is serving, one gate at a time,
// and requires the case that claims to guard that gate to FAIL. `functions
// serve` re-reads a changed module on the next request (measured ~1.4 s), so
// this costs no second host boot and no second stack - which is what the
// followup entry had priced it at.
//
// One mutation per round, not a bundle, because the point is ATTRIBUTION: a
// blanket break proves only that each case notices a dead function, which is
// the weaker claim § 788 already makes about everything else. `spares` is how
// a round says what must NOT move, and it is what separates "this case
// measures the compare" from "this case measures that the gate exists at all".
// Two of the entries below found that difference: the bare-GET secret test was
// answered 403 by the verify-token gate whatever the secret gate did, and the
// verify-token gate itself killed nothing in the file.
//
// COVERAGE IS ENFORCED, on three edges, and it took all three to make the
// obligation true. `unmeasuredCases` requires every case the baseline RAN to
// appear in some mutation's `kills`; `phantomKills` requires every named case
// to have run. Those two alone left the claim this comment used to make - "a
// new case fails this guard until a mutation names it" - false for a case that
// does not run: `parseJunit` drops deno's `<skipped/>` entries, so a case whose
// `ignore:` gate is never false in CI is in neither set and is measured by
// nothing while reading as green. `declaredCases` + `unnamedDeclaredCases` are
// the third edge, static and host-free: every case the FILE declares must be
// killed by a mutation or carry an `UNMEASURED_CASES` reason it is not owed
// one. With `ran ⊆ kills`, `kills ⊆ ran` and `declared ⊆ kills`, the three sets
// are one. An unmeasured integration case is exactly what § 815 closed.
//
//   --report    print the per-mutation verdict table
//   --json      machine-readable result
//   default     guard: fail on a survivor, a moved spare, or an unmeasured case
//
// Needs: a running local Supabase stack + an env-loaded `supabase functions
// serve` host (the `edge-functions` CI job's boot step), SUPABASE_TEST_URL, and
// the same webhook secrets that host loaded. Without SUPABASE_SERVICE_ROLE_KEY
// the four side-effect cases skip in the baseline and their mutations are
// skipped with them.
//
// Run: node apps/backend/scripts/check_served_envelope_mutations.mjs
// Unit tests: node --test apps/backend/scripts/check_served_envelope_mutations.test.mjs

import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { parseJunit } from './check_edge_function_test_vacuity.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const BACKEND_DIR = resolve(HERE, '..');
export const FUNCTIONS_DIR = join(BACKEND_DIR, 'supabase', 'functions');
export const TEST_FILE = 'supabase/functions/_shared/handler_envelope.test.ts';

// Mirrors the defaults `handler_envelope.test.ts` itself falls back to, so a
// developer running against a CI-shaped `.env.local` needs to export nothing.
export const STRAVA_WEBHOOK_SECRET =
  process.env.STRAVA_WEBHOOK_SECRET ?? 'ci-strava-webhook-secret-32chars-ok';
export const STRAVA_VERIFY_TOKEN =
  process.env.STRAVA_VERIFY_TOKEN ?? 'ci-strava-verify-token-32-chars-ok';
export const CRON_SECRET =
  process.env.CRON_SECRET ?? 'ci-cron-secret-at-least-32-chars-ok';

// A `beacon` is a SECOND edit in the same file whose only job is to be visible
// over HTTP. The four side-effect mutations change a database write, not a
// response, so nothing about the reply says whether the host has picked the
// mutant up yet - and a round that ran against the pre-mutation worker would
// report a survivor that does not exist. The beacon flips a status code no
// case in the round asserts, and the round waits for that flip.
const METHOD_GATE_405 = "return Response.json({ error: 'method_not_allowed' }, { status: 405 });";
const METHOD_GATE_BEACON = "return Response.json({ error: 'method_not_allowed' }, { status: 418 });";

/**
 * @typedef {{ fn: string, method?: string, query?: string, headers?: Record<string,string>, body?: string }} Probe
 * @typedef {{ status: number, contains?: string }} Expect
 * @typedef {{
 *   id: string,
 *   file: string,
 *   from: string,
 *   to: string,
 *   beacon?: { file?: string, from: string, to: string },
 *   probe: Probe,
 *   expect: Expect,
 *   kills: string[],
 *   spares: string[],
 *   reason: string,
 * }} Mutation
 */

/** @type {Mutation[]} */
export const MUTATIONS = [
  {
    id: 'cron-gate-open',
    file: 'refresh-tokens/index.ts',
    from: 'if (!token || !timingSafeEqual(token, cronSecret)) {',
    to: 'if (false) {',
    probe: { fn: 'refresh-tokens', method: 'POST' },
    expect: { status: 200 },
    kills: [
      'refresh-tokens: 403 on missing Authorization header',
      'refresh-tokens: 403 on wrong CRON_SECRET',
      'refresh-tokens: 403 on a non-Bearer Authorization header',
    ],
    spares: [],
    reason:
      'the cron-secret gate is gone entirely, so the pg_cron-only function is publicly invokable ' +
      'and would loop every integrations row through Strava OAuth for any caller',
  },
  {
    id: 'cron-compare-accepts',
    file: 'refresh-tokens/index.ts',
    from: '!token || !timingSafeEqual(token, cronSecret)',
    to: '!token',
    probe: { fn: 'refresh-tokens', method: 'POST', headers: { Authorization: 'Bearer wrong-secret' } },
    expect: { status: 200 },
    kills: ['refresh-tokens: 403 on wrong CRON_SECRET'],
    spares: [
      'refresh-tokens: 403 on missing Authorization header',
      'refresh-tokens: 403 on a non-Bearer Authorization header',
    ],
    reason:
      'any bearer at all is accepted while an absent one is still refused - the sharper half of the ' +
      'gate. The two spares are what say the wrong-secret case measures the COMPARE and not merely ' +
      'that a header is required',
  },
  {
    id: 'cron-sweep-count-fabricated',
    file: 'refresh-tokens/index.ts',
    from: '  const { refreshed } = await refreshExpiringStravaTokens(supabase);\n' +
      '  return Response.json({ refreshed });',
    to: '  await refreshExpiringStravaTokens(supabase);\n' +
      '  return Response.json({ refreshed: 1 });',
    probe: {
      fn: 'refresh-tokens',
      method: 'POST',
      headers: { Authorization: `Bearer ${CRON_SECRET}` },
    },
    expect: { status: 200, contains: '"refreshed":1' },
    kills: [
      'refresh-tokens: the correct cron bearer is accepted and the sweep completes ' +
        'without reaching Strava',
    ],
    spares: [
      'refresh-tokens: 403 on missing Authorization header',
      'refresh-tokens: 403 on wrong CRON_SECRET',
      'refresh-tokens: 403 on a non-Bearer Authorization header',
    ],
    reason:
      'the hourly job records a count the sweep never produced, so a run that rotated nothing ' +
      'reports a success. The three spares are what say this is measured PAST the gate: none of ' +
      'them ever gets through it, so a gate that refused every caller would pass all three ' +
      'and leave the accepted path unmeasured. The probe carries the real cron bearer for the ' +
      'same reason the case does, and deliberately does NOT close the gate: the refusal branch ' +
      'spends an ipBucketKey rate-limit token per call, and twenty polls of it would put the ' +
      "429 those three cases cannot distinguish from a 403 into some later round's answer",
  },
  {
    id: 'strava-secret-gate-open',
    file: 'strava-webhook/index.ts',
    from: 'if (!suppliedSecret || !timingSafeEqual(suppliedSecret, webhookSecret)) {',
    to: 'if (false) {',
    probe: { fn: 'strava-webhook', method: 'POST', query: '?secret=wrong', body: '{}' },
    expect: { status: 200 },
    kills: [
      'strava-webhook: 403 on POST with no ?secret=',
      'strava-webhook: 403 on GET with no ?secret=',
      'strava-webhook: 403 on POST with wrong ?secret= value',
    ],
    spares: [],
    reason:
      'the URL secret is the only auth on the POST surface (Strava does not sign payloads), so an ' +
      'open gate lets anyone inject activity events',
  },
  {
    id: 'strava-verify-token-gate-open',
    file: 'strava-webhook/index.ts',
    from: 'if (!expectedToken || !timingSafeEqual(verifyToken, expectedToken)) {',
    to: 'if (false) {',
    probe: {
      fn: 'strava-webhook',
      query:
        `?secret=${STRAVA_WEBHOOK_SECRET}&hub.mode=subscribe&hub.challenge=probe` +
        '&hub.verify_token=wrong-token',
    },
    expect: { status: 200 },
    kills: ['strava-webhook: 403 on GET with valid ?secret= but wrong hub.verify_token'],
    spares: ['strava-webhook: GET handshake echoes hub.challenge on correct secret + verify_token'],
    reason:
      'the handshake becomes completable with the URL secret alone. This mutation killed NOTHING ' +
      'before § 815 - the gate had no case at all, and the bare-GET secret test that looked like ' +
      'its coverage was being answered by this gate rather than measuring it',
  },
  {
    id: 'strava-handshake-echo-dropped',
    file: 'strava-webhook/index.ts',
    from: "Response.json({ 'hub.challenge': challenge })",
    to: 'Response.json({ ok: true })',
    probe: {
      fn: 'strava-webhook',
      query:
        `?secret=${STRAVA_WEBHOOK_SECRET}&hub.mode=subscribe&hub.challenge=probe` +
        `&hub.verify_token=${STRAVA_VERIFY_TOKEN}`,
    },
    expect: { status: 200, contains: '"ok":true' },
    kills: ['strava-webhook: GET handshake echoes hub.challenge on correct secret + verify_token'],
    spares: ['strava-webhook: 403 on GET with valid ?secret= but wrong hub.verify_token'],
    reason:
      'the handshake answers 200 without echoing the challenge, so Strava silently refuses the ' +
      'subscription and no activity webhook is ever delivered',
  },
  {
    id: 'strava-non-create-early-return-dropped',
    file: 'strava-webhook/index.ts',
    from: "if (event.object_type !== 'activity' || event.aspect_type !== 'create') {",
    to: 'if (false) {',
    probe: {
      fn: 'strava-webhook',
      method: 'POST',
      query: `?secret=${STRAVA_WEBHOOK_SECRET}`,
      body: '{"object_type":"athlete","object_id":1,"aspect_type":"update","owner_id":1,"event_time":1}',
    },
    expect: { status: 400 },
    kills: ['strava-webhook: 200 "OK" on non-create event after valid secret'],
    spares: ['strava-webhook: 400 missing_object_id_or_owner_id on create-shaped event with no ids'],
    reason:
      'every non-actionable event (an athlete update, a delete) is processed as an activity create ' +
      'and burns a webhook_events row',
  },
  {
    id: 'strava-missing-ids-accepted',
    file: 'strava-webhook/index.ts',
    from: 'if (!activityId || !ownerId) {',
    to: 'if (false) {',
    probe: {
      fn: 'strava-webhook',
      method: 'POST',
      query: `?secret=${STRAVA_WEBHOOK_SECRET}`,
      body: '{"object_type":"activity","aspect_type":"create","event_time":1}',
    },
    expect: { status: 400, contains: 'event_outside_freshness_window' },
    kills: ['strava-webhook: 400 missing_object_id_or_owner_id on create-shaped event with no ids'],
    spares: ['strava-webhook: 200 "OK" on non-create event after valid secret'],
    reason: 'an id-less create is carried into the dedupe key and the integrations lookup',
  },
  {
    id: 'revenuecat-method-gate-open',
    file: 'revenuecat-webhook/index.ts',
    from: "if (req.method !== 'POST') {",
    to: 'if (false) {',
    probe: { fn: 'revenuecat-webhook' },
    expect: { status: 401 },
    kills: ['revenuecat-webhook: 405 on GET (POST-only)'],
    spares: ['revenuecat-webhook: 401 missing_signature when no x-revenuecat-hmac header'],
    reason: 'a GET is read for a body and signature-checked rather than refused',
  },
  {
    id: 'revenuecat-missing-signature-accepted',
    file: 'revenuecat-webhook/index.ts',
    from: "return Response.json({ error: 'missing_signature' }, { status: 401 });",
    to: 'return Response.json({ ok: true });',
    probe: { fn: 'revenuecat-webhook', method: 'POST', body: '{}' },
    expect: { status: 200 },
    kills: ['revenuecat-webhook: 401 missing_signature when no x-revenuecat-hmac header'],
    spares: ['revenuecat-webhook: 401 bad_signature on wrong HMAC'],
    reason: 'an unsigned caller is answered 200 - the fail-open shape, one branch above the compare',
  },
  {
    id: 'revenuecat-hmac-compare-accepts',
    file: 'revenuecat-webhook/index.ts',
    from: 'if (!timingSafeEqual(sig, expected)) {',
    to: 'if (false) {',
    probe: {
      fn: 'revenuecat-webhook',
      method: 'POST',
      headers: { 'x-revenuecat-hmac': 'deadbeef' },
      body: '{"event":{}}',
    },
    expect: { status: 400 },
    kills: ['revenuecat-webhook: 401 bad_signature on wrong HMAC'],
    spares: ['revenuecat-webhook: 401 missing_signature when no x-revenuecat-hmac header'],
    reason: 'any signature verifies, so anyone can move a subscription tier',
  },
  {
    id: 'revenuecat-anon-shortcircuit-dropped',
    file: 'revenuecat-webhook/index.ts',
    from: 'if (!userId || isAnonymousAppUserId(userId)) {',
    to: 'if (false) {',
    beacon: { from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'revenuecat-webhook' },
    expect: { status: 418 },
    kills: ['revenuecat-webhook: 200 on valid HMAC + fresh anonymous event'],
    spares: ['revenuecat-webhook: 400 event_outside_freshness_window on stale event'],
    reason:
      "RevenueCat's sandbox `$RCAnonymousID:` users stop short-circuiting and are resolved as real " +
      'user ids. The one case in the file that proves the whole HMAC + freshness + parse chain ' +
      'reaches the end',
  },
  {
    id: 'revenuecat-freshness-ignored',
    file: 'revenuecat-webhook/index.ts',
    from: "if (validateFreshness(eventTsMs, Date.now()) !== 'ok') {",
    to: 'if (false) {',
    beacon: { from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'revenuecat-webhook' },
    expect: { status: 418 },
    kills: ['revenuecat-webhook: 400 event_outside_freshness_window on stale event'],
    spares: ['revenuecat-webhook: 400 missing_event_timestamp_ms when timestamp absent'],
    reason: 'a captured delivery replays at any future time - the replay window is the only sequencer',
  },
  {
    id: 'revenuecat-missing-timestamp-accepted',
    file: 'revenuecat-webhook/index.ts',
    from: 'if (eventTsMs === null) {',
    to: 'if (false) {',
    beacon: { from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'revenuecat-webhook' },
    expect: { status: 418 },
    kills: ['revenuecat-webhook: 400 missing_event_timestamp_ms when timestamp absent'],
    spares: ['revenuecat-webhook: 400 event_outside_freshness_window on stale event'],
    reason: 'a timestamp-less event reaches the freshness gate as null instead of being named',
  },
  {
    id: 'revenuecat-tier-write-dropped',
    file: 'revenuecat-webhook/index.ts',
    from: 'patch.subscription_tier = newTier;',
    to: 'void newTier;',
    beacon: { from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'revenuecat-webhook' },
    expect: { status: 418 },
    kills: [
      'revenuecat-webhook: writes user_profiles — pro → dedupe → free → lifetime → ' +
        'lifetime-protected PRODUCT_CHANGE',
    ],
    spares: [],
    reason:
      'the decided tier is never written, so a paying subscriber stays free. The response is 200 ' +
      'either way, which is why this round carries a beacon',
  },
  {
    id: 'auth-email-method-gate-open',
    file: 'auth-email/handler.ts',
    from: "if (req.method !== 'POST') {",
    to: 'if (false) {',
    probe: { fn: 'auth-email' },
    expect: { status: 401 },
    kills: ['auth-email: 405 on GET (POST-only)'],
    spares: ['auth-email: 401 bad_signature on a wrong signature'],
    reason: 'a GET reaches the Standard Webhooks verification rather than being refused',
  },
  {
    id: 'auth-email-missing-headers-accepted',
    file: 'auth-email/lib.ts',
    from: "return 'missing_headers';",
    to: "return 'ok';",
    probe: { fn: 'auth-email', method: 'POST', body: '{}' },
    expect: { status: 200, contains: 'no_recipient' },
    kills: ['auth-email: 401 missing_headers when the Standard Webhooks headers are absent'],
    spares: ['auth-email: 401 bad_signature on a wrong signature'],
    reason:
      'a caller supplying no webhook-id / -timestamp / -signature at all verifies, so anyone can ' +
      "make GoTrue's send-email hook render and send auth mail. The mutant answered 503 " +
      'smtp_not_configured until the boot step started configuring SMTP for the positive case; ' +
      'it now reaches the send PLAN and reports no_recipient for a bodyless probe, which is the ' +
      'mutation getting further rather than less far - the SMTP guard had been standing in for a ' +
      'signature check that was no longer there',
  },
  {
    id: 'auth-email-signature-compare-accepts',
    file: 'auth-email/lib.ts',
    from: "if (timingSafeEqual(sig, expected)) return 'ok';",
    to: "return 'ok';",
    beacon: { file: 'auth-email/handler.ts', from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'auth-email' },
    expect: { status: 418 },
    kills: ['auth-email: 401 bad_signature on a wrong signature'],
    spares: ['auth-email: 401 missing_headers when the Standard Webhooks headers are absent'],
    reason: 'any signature verifies once the three headers are merely present',
  },
  {
    id: 'auth-email-metadata-locale-ignored',
    file: 'auth-email/lib.ts',
    from: "  if (typeof metadataLocale === 'string' && metadataLocale.trim() !== '') {\n" +
      '    return normalizeEmailLocale(metadataLocale);\n' +
      '  }',
    to: '  if (false) {}',
    beacon: { file: 'auth-email/handler.ts', from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'auth-email' },
    expect: { status: 418 },
    kills: [
      "auth-email: a correctly signed signup hook renders in the recipient's locale " +
        'and delivers over SMTP',
    ],
    spares: [
      'auth-email: 401 missing_headers when the Standard Webhooks headers are absent',
      'auth-email: 401 bad_signature on a wrong signature',
    ],
    reason:
      'a brand-new signup has no user_settings row, so the metadata locale is the ONLY locale a ' +
      'confirmation mail can be rendered in - dropping it silently sends every new account its ' +
      'confirmation in English. The response is {} either way, which is why this round carries ' +
      'a beacon; the two spares say the refusals do not move, and the 405 case is deliberately ' +
      'neither, because the beacon is the status it asserts',
  },
  {
    id: 'stripe-account-updated-flag-dropped',
    file: 'stripe-events-webhook/index.ts',
    from: 'charges_enabled: account.chargesEnabled,',
    to: 'charges_enabled: false,',
    beacon: { from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'stripe-events-webhook' },
    expect: { status: 418 },
    kills: [
      'stripe-events-webhook: account.updated mirrors capability flags into ' +
        'instructor_payout_accounts + dedupes a replay',
    ],
    spares: [],
    reason:
      "Stripe's capability flag stops reaching the column, so an onboarded instructor is shown as " +
      'unable to take charges forever',
  },
  {
    id: 'stripe-donation-paid-write-dropped',
    file: 'stripe-events-webhook/index.ts',
    from: "    .from('donations')\n    .update({\n      status: 'paid',",
    to: "    .from('donations')\n    .update({\n      status: 'pending',",
    beacon: { from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'stripe-events-webhook' },
    expect: { status: 418 },
    kills: [
      'stripe-events-webhook: donation checkout.session.completed marks donations paid + dedupes ' +
        'a replay + charge.refunded refunds it',
    ],
    spares: [],
    reason: 'a settled donation stays pending, so a charged card shows as an unpaid pledge',
  },
  {
    id: 'stripe-order-expiry-cas-dropped',
    file: 'stripe-events-webhook/index.ts',
    from: "    .from('event_orders')\n    .update({ status: next })",
    to: "    .from('event_orders')\n    .update({ status: 'pending' })",
    beacon: { from: METHOD_GATE_405, to: METHOD_GATE_BEACON },
    probe: { fn: 'stripe-events-webhook' },
    expect: { status: 418 },
    kills: ['stripe-events-webhook: event-order checkout.session.expired CAS pending->canceled'],
    spares: [],
    reason:
      'an expired checkout never releases its soft reservation, so the seat is held against ' +
      'capacity by an order nobody paid for',
  },
];

/**
 * Regex-escape a Deno test name for `--filter "/.../"`.
 * @param {string} s
 * @returns {string}
 */
export function escapeForFilter(s) {
  return s.replace(/[.*+?^${}()|[\]\\\-]/g, '\\$&');
}

/**
 * The single `--filter` expression matching exactly `names`.
 * @param {string[]} names
 * @returns {string}
 */
export function filterFor(names) {
  return `/^(${names.map(escapeForFilter).join('|')})$/`;
}

/**
 * Reasons `MUTATIONS` is not a usable table, as messages. Empty when it is.
 * @param {Mutation[]} mutations
 * @param {(rel: string) => string} readFn reads a functions-tree file
 * @returns {string[]}
 */
export function validateMutations(mutations, readFn) {
  /** @type {string[]} */
  const errs = [];
  /** @type {Set<string>} */
  const ids = new Set();
  for (const m of mutations) {
    if (ids.has(m.id)) errs.push(`duplicate mutation id ${m.id}`);
    ids.add(m.id);
    if (!m.kills.length) errs.push(`${m.id} declares no kills, so it measures nothing`);
    if (!m.reason.trim()) errs.push(`${m.id} carries no reason`);
    if (m.from === m.to) errs.push(`${m.id} replaces its anchor with itself`);
    for (const name of m.spares) {
      if (m.kills.includes(name)) errs.push(`${m.id} lists "${name}" as both a kill and a spare`);
    }
    if (!Number.isInteger(m.expect?.status) || m.expect.status < 100 || m.expect.status > 599) {
      errs.push(`${m.id} declares no HTTP status for its mutant's probe answer`);
    } else if (GATEWAY_STATUSES.has(m.expect.status) && !m.expect.contains) {
      // 502/503/504 are what a restarting runtime answers with, so a round
      // waiting for a bare one of those cannot tell the mutant from the reload
      // and would run against a half-up host - the CI failure § 815 records.
      errs.push(
        `${m.id} expects a gateway status (${m.expect.status}), which is also what the runtime ` +
          'answers mid-restart, so it must also declare a `contains` only the mutant can produce',
      );
    }
    if (m.expect?.contains !== undefined && !m.expect.contains.length) {
      errs.push(`${m.id} declares an empty \`contains\``);
    }
    let src;
    try {
      src = readFn(m.file);
    } catch {
      errs.push(`${m.id} names ${m.file}, which does not exist`);
      continue;
    }
    const n = src.split(m.from).length - 1;
    if (n !== 1) {
      errs.push(
        `${m.id} anchor occurs ${n} times in ${m.file} (needs exactly 1): ${JSON.stringify(m.from)}`,
      );
    }
    if (m.beacon) {
      const bfile = m.beacon.file ?? m.file;
      let bsrc = '';
      try {
        bsrc = bfile === m.file ? src : readFn(bfile);
      } catch {
        errs.push(`${m.id} beacon names ${bfile}, which does not exist`);
        continue;
      }
      const b = bsrc.split(m.beacon.from).length - 1;
      if (b !== 1) {
        errs.push(
          `${m.id} beacon anchor occurs ${b} times in ${bfile} (needs exactly 1): ` +
            JSON.stringify(m.beacon.from),
        );
      }
    }
  }
  return errs;
}

/**
 * @typedef {{ name: string, ignore: string }} DeclaredCase
 */

/**
 * Whitespace and `//` / block comments between two tokens.
 * @param {string} src
 * @param {number} i
 * @returns {number}
 */
function skipTrivia(src, i) {
  for (;;) {
    while (i < src.length && /\s/.test(src[i])) i++;
    if (src.startsWith('//', i)) {
      const nl = src.indexOf('\n', i);
      i = nl === -1 ? src.length : nl + 1;
      continue;
    }
    if (src.startsWith('/*', i)) {
      const end = src.indexOf('*/', i);
      i = end === -1 ? src.length : end + 2;
      continue;
    }
    return i;
  }
}

/**
 * One string literal starting at `i`, with its escapes resolved.
 * @param {string} src
 * @param {number} i
 * @returns {{ value: string, end: number } | null}
 */
function readStringLiteral(src, i) {
  const quote = src[i];
  if (quote !== "'" && quote !== '"' && quote !== '`') return null;
  let out = '';
  let j = i + 1;
  while (j < src.length) {
    const ch = src[j];
    if (ch === '\\') {
      const esc = src[j + 1];
      out += esc === 'n' ? '\n' : esc === 't' ? '\t' : esc;
      j += 2;
      continue;
    }
    if (ch === quote) return { value: out, end: j + 1 };
    // A substitution makes the reported name unknowable from the source, and a
    // name the census cannot key on is a case it cannot account for.
    if (quote === '`' && ch === '$' && src[j + 1] === '{') return null;
    out += ch;
    j++;
  }
  return null;
}

/**
 * A run of adjacent string literals joined by `+`, which is how every multi-line
 * case name in the file is written. Splitting on `+` instead would cut the four
 * names that carry a literal ` + ` of their own.
 * @param {string} src
 * @param {number} i
 * @returns {{ value: string, end: number } | null}
 */
function readConcatenatedString(src, i) {
  let j = skipTrivia(src, i);
  const first = readStringLiteral(src, j);
  if (!first) return null;
  let value = first.value;
  j = first.end;
  for (;;) {
    const k = skipTrivia(src, j);
    if (src[k] !== '+') return { value, end: j };
    const next = readStringLiteral(src, skipTrivia(src, k + 1));
    if (!next) return { value, end: j };
    value += next.value;
    j = next.end;
  }
}

/**
 * Every `Deno.test` the file DECLARES, in source order, each with the
 * expression its `ignore:` is gated on ('' when it carries none).
 *
 * The runtime half of this guard enumerates the cases that RAN, which is a
 * strictly smaller set: `parseJunit` drops deno's `<skipped/>` entries, so a
 * case whose `ignore:` gate is never false in CI is absent from `ran` — absent
 * from `unmeasuredCases`, which filters `ran`, and absent from `phantomKills`
 * unless some mutation happens to name it. Declared-but-never-run-and-unnamed
 * is therefore a case that asserts nothing and reads as green, which is the
 * exact shape § 815 closed one layer out. This is the source-side census that
 * closes it: with `ran ⊆ kills` (unmeasuredCases), `kills ⊆ ran`
 * (phantomKills) and `declared ⊆ kills` (here), the three sets are one.
 *
 * Refuses rather than skips on a form it cannot read: a parser that silently
 * returned nothing would make the census vacuous, which is the failure it
 * exists to prevent.
 * @param {string} src
 * @returns {DeclaredCase[]}
 */
export function declaredCases(src) {
  /** @type {DeclaredCase[]} */
  const out = [];
  const marker = 'Deno.test(';
  for (let i = src.indexOf(marker); i !== -1; i = src.indexOf(marker, i + 1)) {
    const line = src.slice(0, i).split('\n').length;
    let j = skipTrivia(src, i + marker.length);
    if (src[j] !== '{') {
      throw new Error(
        `${TEST_FILE}:${line} declares a Deno.test in a form this census cannot read (expected ` +
          'the object form `Deno.test({ name: ... })`). Write it in the object form, or teach ' +
          'declaredCases the new one — leaving it unparsed makes the census silently miss a case.',
      );
    }
    j = skipTrivia(src, j + 1);
    if (!src.startsWith('name:', j)) {
      throw new Error(
        `${TEST_FILE}:${line} declares a Deno.test whose first property is not \`name:\`, so the ` +
          'census cannot say which case it is. Put the name first.',
      );
    }
    const nameTok = readConcatenatedString(src, j + 'name:'.length);
    if (!nameTok) {
      throw new Error(
        `${TEST_FILE}:${line} declares a Deno.test whose name is not a string literal (a template ` +
          'substitution or a variable). The census keys on the name deno reports, so it must be ' +
          'written out.',
      );
    }
    const rest = src.slice(nameTok.end, src.indexOf('fn:', nameTok.end) + 1);
    const ig = /(?:^|[\s,{])ignore:\s*([^\n,]*)/.exec(rest);
    out.push({ name: nameTok.value, ignore: (ig?.[1] ?? '').trim() });
  }
  return out;
}

/**
 * Declared cases no mutation measures and none is owed, each with the reason.
 *
 * The § 1273 shape: a guard that demands a measurement demands either the
 * measurement or a declared reason it is not owed, and `staleExemptions` fails
 * the moment a reason stops describing the file.
 * @type {{ name: string, reason: string }[]}
 */
export const UNMEASURED_CASES = [
  {
    name: 'handler-envelope tests skipped',
    reason:
      'not an assertion. It is registered only inside `if (SKIP)` — the branch taken when ' +
      'SUPABASE_TEST_URL is unset — carries `ignore: true` and an empty body, and exists so ' +
      '`deno test` prints one ignored case instead of "no tests". It cannot run on the path this ' +
      'guard measures, and a mutation naming it would phantom on every honest run.',
  },
];

/**
 * Cases the file declares that no mutation kills and no exemption excuses.
 * @param {DeclaredCase[]} declared
 * @param {Mutation[]} mutations
 * @param {{ name: string, reason: string }[]} exemptions
 * @returns {string[]}
 */
export function unnamedDeclaredCases(declared, mutations, exemptions = UNMEASURED_CASES) {
  const claimed = new Set(mutations.flatMap((m) => m.kills));
  const excused = new Set(exemptions.map((e) => e.name));
  return declared.map((d) => d.name).filter((n) => !claimed.has(n) && !excused.has(n));
}

/**
 * Exemptions that have stopped describing the file: one naming a case that is
 * gone, one whose case a mutation now measures (the exemption is spent, and
 * leaving it lets a later rename slip back through unnamed), and one carrying
 * no reason at all.
 * @param {DeclaredCase[]} declared
 * @param {Mutation[]} mutations
 * @param {{ name: string, reason: string }[]} exemptions
 * @returns {{ name: string, why: string }[]}
 */
export function staleExemptions(declared, mutations, exemptions = UNMEASURED_CASES) {
  const names = new Set(declared.map((d) => d.name));
  const claimed = new Set(mutations.flatMap((m) => m.kills));
  /** @type {{ name: string, why: string }[]} */
  const out = [];
  for (const e of exemptions) {
    if (!e.reason || !e.reason.trim()) {
      out.push({ name: e.name, why: 'carries no reason, so nothing says why it is not owed one' });
    }
    if (!names.has(e.name)) {
      out.push({ name: e.name, why: 'the test file no longer declares a case of that name' });
    } else if (claimed.has(e.name)) {
      out.push({ name: e.name, why: 'a mutation now measures it, so the exemption is spent' });
    }
  }
  return out;
}

/**
 * Cases the baseline ran that no mutation claims to kill.
 * @param {string[]} ran
 * @param {Mutation[]} mutations
 * @returns {string[]}
 */
export function unmeasuredCases(ran, mutations) {
  const claimed = new Set(mutations.flatMap((m) => m.kills));
  return ran.filter((name) => !claimed.has(name));
}

/**
 * Kills a mutation declares that the baseline never ran.
 * @param {string[]} ran
 * @param {Mutation[]} mutations
 * @returns {{ id: string, name: string }[]}
 */
export function phantomKills(ran, mutations) {
  const seen = new Set(ran);
  /** @type {{ id: string, name: string }[]} */
  const out = [];
  for (const m of mutations) {
    for (const name of m.kills) if (!seen.has(name)) out.push({ id: m.id, name });
  }
  return out;
}

const TEST_URL = (process.env.SUPABASE_TEST_URL ?? '').replace(/\/$/, '');
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const RELOAD_TIMEOUT_MS = 30_000;
const RELOAD_POLL_MS = 250;

// strava-webhook rate-limits its anonymous callers 60/hour BEFORE the secret
// check, and its three rejection cases tolerate the 429 as shared-runner noise.
// That tolerance is exactly what would turn a bucket this guard filled itself
// into a phantom survivor: twenty rounds of probes and re-runs spend far more
// than sixty calls, and a 429 satisfies "the secret gate refused" without the
// gate being consulted. Emptying the bucket between rounds is what keeps every
// strava verdict a statement about the gate.
export const STRAVA_ANON_BUCKET = 'strava-webhook:anon';

/** What a restarting edge runtime answers with, rather than any mutant. */
export const GATEWAY_STATUSES = new Set([502, 503, 504]);

async function clearStravaRateLimit() {
  try {
    const res = await fetch(
      `${TEST_URL}/rest/v1/rate_limits?bucket=eq.${encodeURIComponent(STRAVA_ANON_BUCKET)}`,
      {
        method: 'DELETE',
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        },
      },
    );
    await res.body?.cancel();
    return res.ok;
  } catch {
    return false;
  }
}

/** @param {string} rel */
const funcPath = (rel) => join(FUNCTIONS_DIR, rel);

/**
 * Deno's own output, indented and capped, for quoting inside a diagnosis.
 * @param {string} text
 * @returns {string}
 */
function indent(text) {
  const lines = text.replace(/\u001b\[[0-9;]*m/g, '').trimEnd().split('\n');
  const shown = lines.length > 60 ? [...lines.slice(0, 30), '  ...', ...lines.slice(-30)] : lines;
  return shown.map((l) => `    ${l}`).join('\n');
}

/**
 * @param {Probe} probe
 * @returns {Promise<string>} a status+body fingerprint
 */
async function probeOnce(probe) {
  if (probe.fn === 'strava-webhook') await clearStravaRateLimit();
  const url = `${TEST_URL}/functions/v1/${probe.fn}${probe.query ?? ''}`;
  try {
    const res = await fetch(url, {
      method: probe.method ?? 'GET',
      headers: { 'content-type': 'application/json', ...(probe.headers ?? {}) },
      body: probe.body,
    });
    const text = await res.text();
    return `${res.status} ${text}`;
  } catch (err) {
    return `ERR ${/** @type {Error} */ (err).message}`;
  }
}

/**
 * The HTTP status a fingerprint carries, or -1 for a transport failure.
 * @param {string} fingerprint
 * @returns {number}
 */
export function statusOf(fingerprint) {
  const m = /^(\d{3}) /.exec(fingerprint);
  return m ? Number(m[1]) : -1;
}

/**
 * Whether a fingerprint is the answer `expect` describes.
 * @param {string} fingerprint
 * @param {Expect} expect
 * @returns {boolean}
 */
export function satisfies(fingerprint, expect) {
  if (statusOf(fingerprint) !== expect.status) return false;
  return expect.contains === undefined || fingerprint.includes(expect.contains);
}

/**
 * Wait until the probe DOES NOT merely differ from `before` but settles on the
 * answer the mutation declares, twice in a row and byte-identically.
 *
 * "Differs from before" is what this used to require, and it is what failed in
 * real CI: `functions serve` restarts the runtime around a file change, and a
 * request landing in that window is answered by kong with a gateway 503 or by
 * a reset connection. Both differ from `before`, so two of them in a row let
 * the round proceed against a host that was not serving the mutant at all -
 * every case then failed on the wrong answer, which scores the kills as killed
 * and the SPARES as moved. That is exactly the shape the CI failure took, and
 * it is invisible locally because the restart window is milliseconds on a warm
 * workstation and seconds on a loaded two-core runner.
 * @param {Probe} probe
 * @param {string} before
 * @param {Expect} expect
 * @returns {Promise<{ ok: boolean, last: string }>}
 */
async function waitForMutant(probe, before, expect) {
  const deadline = Date.now() + RELOAD_TIMEOUT_MS;
  let last = '';
  let prevGood = '';
  while (Date.now() < deadline) {
    const fp = await probeOnce(probe);
    last = fp;
    const good = fp !== before && satisfies(fp, expect);
    if (good && fp === prevGood) return { ok: true, last: fp };
    prevGood = good ? fp : '';
    await new Promise((r) => setTimeout(r, RELOAD_POLL_MS));
  }
  return { ok: false, last };
}

/**
 * Wait until the probe is byte-identically back to its pre-mutation answer,
 * twice in a row. This half was always exact, which is why the restore never
 * mis-fired the way the mutation wait did.
 * @param {Probe} probe
 * @param {string} before
 * @returns {Promise<{ ok: boolean, last: string }>}
 */
async function waitForRestore(probe, before) {
  const deadline = Date.now() + RELOAD_TIMEOUT_MS;
  let last = '';
  let streak = 0;
  while (Date.now() < deadline) {
    const fp = await probeOnce(probe);
    last = fp;
    streak = fp === before ? streak + 1 : 0;
    if (streak === 2) return { ok: true, last: fp };
    await new Promise((r) => setTimeout(r, RELOAD_POLL_MS));
  }
  return { ok: false, last };
}

/**
 * Every case the run reported, keyed by test name (the JUnit `classname` carries
 * a `./` prefix deno adds, so the file half is not a stable key), plus deno's
 * own output. The output is what a failing round has to quote: a guard that
 * says "this case stopped passing" without saying WHY sends the reader back to
 * a machine that no longer has the mutant applied.
 * @param {string} filter
 * @param {string} junitPath
 * @returns {Promise<{ report: Map<string, boolean>, output: string }>}
 */
async function runFiltered(filter, junitPath) {
  await clearStravaRateLimit();
  const args = [
    'test',
    '--no-check',
    '--allow-net',
    '--allow-env',
    `--junit-path=${junitPath}`,
    TEST_FILE,
  ];
  if (filter) args.splice(5, 0, `--filter=${filter}`);
  const res = spawnSync('deno', args, {
    cwd: BACKEND_DIR,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let xml = '';
  try {
    xml = readFileSync(junitPath, 'utf8');
  } catch {
    throw new Error(
      `deno test produced no JUnit report.\nstdout:\n${res.stdout}\nstderr:\n${res.stderr}`,
    );
  }
  /** @type {Map<string, boolean>} */
  const report = new Map();
  for (const t of parseJunit(xml).values()) report.set(t.name, t.passed);
  return { report, output: `${res.stdout ?? ''}${res.stderr ?? ''}` };
}

async function main() {
  const argv = process.argv.slice(2);
  if (!TEST_URL) {
    console.error(
      '::error::SUPABASE_TEST_URL is unset, so the handler-envelope suite would skip every case ' +
        'and this guard would measure nothing. Boot the stack and an env-loaded `supabase ' +
        'functions serve` first, then set SUPABASE_TEST_URL=http://127.0.0.1:54321.',
    );
    process.exit(1);
  }

  if (!SERVICE_ROLE_KEY) {
    console.error(
      '::error::SUPABASE_SERVICE_ROLE_KEY is unset. This guard needs it for two reasons, and ' +
        'neither is optional: the four side-effect cases skip without it, and it is how the ' +
        `${STRAVA_ANON_BUCKET} rate-limit bucket is emptied between rounds. Left full, the ` +
        "429 those cases tolerate as runner noise would read as the secret gate's refusal and " +
        'every strava mutation would report a survivor it did not earn. Read the key with ' +
        '`supabase status -o env`.',
    );
    process.exit(1);
  }

  // Checked once, and refused rather than warned about: an unchecked clear is
  // the same silence as an unchecked assertion. A full bucket answers 429,
  // which three strava cases tolerate as runner noise, so a clear that quietly
  // does nothing turns those rounds into survivors nobody earned.
  if (!(await clearStravaRateLimit())) {
    console.error(
      `::error::Could not empty the ${STRAVA_ANON_BUCKET} rate-limit bucket through the REST API, ` +
        'so this guard cannot keep a 429 out of the strava rounds - and a 429 satisfies "the ' +
        'secret gate refused" without the gate being consulted. Check SUPABASE_SERVICE_ROLE_KEY ' +
        'and that SUPABASE_TEST_URL points at a stack whose rate_limits table is reachable.',
    );
    process.exit(1);
  }

  const tableErrs = validateMutations(MUTATIONS, (rel) => readFileSync(funcPath(rel), 'utf8'));
  if (tableErrs.length) {
    for (const e of tableErrs) {
      console.error(
        `::error::The served-tree mutation table no longer matches the source: ${e}. The gate it ` +
          'named was renamed or rewritten - re-anchor the mutation on the line that now guards it, ' +
          'rather than deleting the entry, or the case it measures goes back to unmeasured.',
      );
    }
    process.exit(1);
  }

  const workdir = mkdtempSync(join(tmpdir(), 'served-envelope-'));
  /** @type {Map<string, string>} */
  const originals = new Map();
  const restore = () => {
    for (const [rel, src] of originals) writeFileSync(funcPath(rel), src);
  };
  const bail = () => {
    restore();
    process.exit(130);
  };
  process.on('SIGINT', bail);
  process.on('SIGTERM', bail);

  try {
    const { report: baseline, output: baselineOutput } = await runFiltered(
      '',
      join(workdir, 'baseline.xml'),
    );
    const ran = [...baseline.keys()];
    const red = ran.filter((name) => baseline.get(name) !== true);
    if (!ran.length) {
      console.error(
        '::error::The handler-envelope suite ran zero cases against the served host, so nothing ' +
          'could be mutation-checked. SUPABASE_TEST_URL is set but every case was skipped or ' +
          'filtered - check the env-loaded functions host is actually serving.',
      );
      process.exit(1);
    }
    if (red.length) {
      console.error(
        `::error::The handler-envelope suite is not green before the mutation (${red.length} ` +
          'failing). Vacuity cannot be measured against a red baseline. First failure: ' +
          `${red[0]}\n${baselineOutput}`,
      );
      process.exit(1);
    }

    const phantoms = phantomKills(ran, MUTATIONS);
    const active = MUTATIONS.filter((m) => m.kills.every((k) => ran.includes(k)));
    const skipped = MUTATIONS.filter((m) => !active.includes(m));

    /** @type {{ id: string, survivors: string[], movedSpares: string[], absent: string[], reloaded: boolean, output: string, lastProbe: string }[]} */
    const results = [];
    /** @param {string} rel */
    const remember = (rel) => {
      if (!originals.has(rel)) originals.set(rel, readFileSync(funcPath(rel), 'utf8'));
      return originals.get(rel) ?? '';
    };
    for (const m of active) {
      const base = remember(m.file);
      const beaconFile = m.beacon?.file ?? m.file;
      const beaconBase = m.beacon ? remember(beaconFile) : '';
      const probe = m.probe;
      const before = await probeOnce(probe);
      if (beaconFile === m.file) {
        let mutated = base.replace(m.from, m.to);
        if (m.beacon) mutated = mutated.replace(m.beacon.from, m.beacon.to);
        writeFileSync(funcPath(m.file), mutated);
      } else {
        writeFileSync(funcPath(m.file), base.replace(m.from, m.to));
        writeFileSync(
          funcPath(beaconFile),
          beaconBase.replace(
            /** @type {{ from: string, to: string }} */ (m.beacon).from,
            /** @type {{ from: string, to: string }} */ (m.beacon).to,
          ),
        );
      }
      const settled = await waitForMutant(probe, before, m.expect);
      const reloaded = settled.ok;
      /** @type {string[]} */
      let survivors = [];
      /** @type {string[]} */
      let movedSpares = [];
      /** @type {string[]} */
      let absent = [];
      let output = '';
      if (reloaded) {
        const names = [...m.kills, ...m.spares];
        const run = await runFiltered(filterFor(names), join(workdir, `${m.id}.xml`));
        output = run.output;
        // A case the report does not carry did not RUN, which is a different
        // fact from failing and must not be reported as one - the filter
        // matched nothing, or deno never reached it.
        absent = names.filter((n) => !run.report.has(n));
        survivors = m.kills.filter((k) => run.report.get(k) === true);
        movedSpares = m.spares.filter((s) => run.report.get(s) === false);
      }
      writeFileSync(funcPath(m.file), base);
      if (beaconFile !== m.file) writeFileSync(funcPath(beaconFile), beaconBase);
      // Do not start the next round against a worker still holding this one's
      // mutant: the probe is back to its pre-mutation answer only once the
      // restored tree is the tree being served.
      const back = await waitForRestore(probe, before);
      if (!back.ok) {
        console.error(
          `::error::After restoring the ${m.id} mutation the served host never went back to its ` +
            `pre-mutation answer (wanted ${JSON.stringify(before.slice(0, 200))}, last saw ` +
            `${JSON.stringify(back.last.slice(0, 200))}), so every later round would measure a ` +
            'tree nobody wrote. Restart `supabase functions serve` and re-run.',
        );
        process.exit(1);
      }
      results.push({
        id: m.id,
        survivors,
        movedSpares,
        absent,
        reloaded,
        output,
        lastProbe: settled.last,
      });
    }

    const killed = active.reduce((n, m) => n + m.kills.length, 0);
    const unmeasured = unmeasuredCases(ran, MUTATIONS);

    if (argv.includes('--json')) {
      console.log(JSON.stringify({ ran, results, unmeasured, phantoms, skipped: skipped.map((m) => m.id) }, null, 2));
      return;
    }

    console.log(
      `${ran.length} served-host handler-envelope cases measured against ${active.length} ` +
        `single-gate mutations of the SERVED Edge Function tree (${killed} declared kills, ` +
        `${results.reduce((n, r) => n + r.survivors.length, 0)} survived, ` +
        `${unmeasured.length} unmeasured).`,
    );
    if (skipped.length) {
      console.log(
        `${skipped.length} mutation(s) skipped - their cases did not run in the baseline: ` +
          skipped.map((m) => m.id).join(', '),
      );
    }
    if (argv.includes('--report')) {
      for (const r of results) {
        const verdict = !r.reloaded
          ? 'HOST NEVER RELOADED'
          : r.survivors.length || r.movedSpares.length || r.absent.length
            ? `survivors=${r.survivors.length} movedSpares=${r.movedSpares.length} ` +
              `didNotRun=${r.absent.length}`
            : 'ok';
        console.log(`  ${r.id.padEnd(42)} ${verdict}`);
        if (verdict !== 'ok' && verdict !== 'HOST NEVER RELOADED') console.log(indent(r.output));
      }
      return;
    }

    let bad = false;
    for (const r of results) {
      const m = active.find((x) => x.id === r.id);
      if (!r.reloaded) {
        bad = true;
        console.error(
          `::error::The served host never settled on the answer ${r.id} declares ` +
            `(expect ${JSON.stringify(m?.expect)}), so nothing was measured about it. Last seen: ` +
            `${JSON.stringify(r.lastProbe.slice(0, 300))}. A gateway 503 or a reset connection ` +
            'here is the runtime restarting and never coming back; a settled answer that is ' +
            "simply not the declared one means the entry's `expect` is wrong, or the branch it " +
            'opens no longer leads where the table says.',
        );
        continue;
      }
      for (const name of r.survivors) {
        bad = true;
        console.error(
          `::error::"${name}" still passes with the ${r.id} mutation applied to the SERVED tree ` +
            `(${m?.reason}). It is not measuring the gate it names - give it an assertion only the ` +
            'gate can satisfy, the way the bare-GET secret case was given a correct verify token.',
        );
      }
      if (r.survivors.length) console.error(indent(r.output));
      for (const name of r.movedSpares) {
        bad = true;
        console.error(
          `::error::"${name}" is declared a spare of ${r.id} but stopped passing under it, so the ` +
            'round cannot attribute its kills. Either the mutation reaches further than the table ' +
            'claims, the case does not discriminate between the two gates, or the failure is not ' +
            `about the mutation at all - deno said:\n${indent(r.output)}`,
        );
      }
      for (const name of r.absent) {
        bad = true;
        console.error(
          `::error::"${name}" is named by ${r.id} but did not run at all, so nothing was measured ` +
            'about it. The --filter regex matched no case of that name, or deno stopped before ' +
            `reaching it - deno said:\n${indent(r.output)}`,
        );
      }
    }
    for (const p of phantoms) {
      bad = true;
      console.error(
        `::error::Mutation ${p.id} claims to kill "${p.name}", which the baseline never ran. The ` +
          'case was renamed or deleted: re-point the mutation at the case that guards its gate ' +
          'now, so the gate does not go back to unmeasured.',
      );
    }
    for (const name of unmeasured) {
      bad = true;
      console.error(
        `::error::"${name}" ran against the served host and no mutation in ` +
          'check_served_envelope_mutations.mjs claims to kill it, so nothing says it would notice ' +
          'the gate it names breaking. Add a mutation that opens that gate (decisions § 815).',
      );
    }
    if (bad) process.exit(1);
    console.log('Every served-host case is killed by the mutation of the gate it names.');
  } finally {
    restore();
    rmSync(workdir, { recursive: true, force: true });
  }
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url))) {
  await main();
}
