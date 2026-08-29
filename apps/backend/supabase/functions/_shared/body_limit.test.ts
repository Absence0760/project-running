/// Run with `cd apps/backend && deno test supabase/functions/_shared/body_limit.test.ts`.
/// (No allow-net flag needed — this module is pure.)
///
/// Pins the streaming body-cap helpers from migration commit 978b4c9
/// (audit pass-2). The header fast-path (`enforceBodyLimit`) was
/// already in place; pass-2 closed the chunked-transfer-encoding
/// bypass by adding `readJsonWithLimit` / `readTextWithLimit` which
/// count bytes as they read and cancel the source on overflow.
///
/// All seven Edge Function callers (parkrun-import, delete-account,
/// export-data, strava-import, strava-webhook, revenuecat-webhook,
/// clip-public-track) migrated to these helpers.

import {
  assertEquals,
  assertStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  discardBody,
  enforceBodyLimit,
  readJsonWithLimit,
  readTextWithLimit,
} from './body_limit.ts';

// Helper — build a request with a Content-Length header pre-set.
function reqWithContentLength(len: number, body = ''): Request {
  return new Request('http://x.test/', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'content-length': String(len),
    },
    body,
  });
}

// Helper — build a chunked-transfer-encoding-style request: no
// Content-Length, body is a stream that emits N bytes total. The
// pre-pass-2 `enforceBodyLimit` would let this through (no header to
// check); the streaming readers must catch it.
function reqWithChunkedBody(totalBytes: number): Request {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      // Emit in 4 KB chunks so the reader has to count across them.
      const chunkSize = 4096;
      let written = 0;
      while (written < totalBytes) {
        const remaining = Math.min(chunkSize, totalBytes - written);
        controller.enqueue(new Uint8Array(remaining).fill(0x20)); // ASCII space
        written += remaining;
      }
      controller.close();
    },
  });
  return new Request('http://x.test/', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: stream,
  });
}

// ─────────────── enforceBodyLimit (header fast-path) ───────────────

Deno.test('enforceBodyLimit — accepts a Content-Length under the cap', () => {
  const req = reqWithContentLength(1024, '{}');
  assertStrictEquals(enforceBodyLimit(req, 4096), null);
});

Deno.test('enforceBodyLimit — rejects an oversize Content-Length with 413', async () => {
  const req = reqWithContentLength(8 * 1024, '{}');
  const resp = enforceBodyLimit(req, 4096);
  assertStrictEquals(resp?.status, 413);
  const body = await resp!.json();
  assertEquals(body.error, 'request body too large');
  assertStrictEquals(body.max_bytes, 4096);
});

Deno.test('enforceBodyLimit — missing Content-Length is NOT rejected by the fast path', () => {
  // The fast path is a header-only check. A chunked-transfer request
  // has no Content-Length and must fall through to the streaming
  // readers — which is the bug the streaming helpers exist to close.
  const req = reqWithChunkedBody(0);
  assertStrictEquals(enforceBodyLimit(req, 4096), null);
});

// ─────────────── readJsonWithLimit (chunked-transfer protection) ───────────────

Deno.test('readJsonWithLimit — accepts a small JSON body', async () => {
  const req = new Request('http://x.test/', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{"hello":"world"}',
  });
  const out = await readJsonWithLimit<{ hello: string }>(req, 4096);
  assertStrictEquals('body' in out, true);
  if ('body' in out) {
    assertEquals(out.body.hello, 'world');
  }
});

Deno.test('readJsonWithLimit — rejects a chunked-transfer body that exceeds the cap', async () => {
  // 8 KB streamed without a Content-Length header — the pre-pass-2
  // `enforceBodyLimit` would have let this through. The streaming
  // reader must catch the overflow and return 413.
  const req = reqWithChunkedBody(8 * 1024);
  const out = await readJsonWithLimit(req, 4096);
  assertStrictEquals('tooLarge' in out, true);
  if ('tooLarge' in out) {
    assertStrictEquals(out.tooLarge.status, 413);
    const body = await out.tooLarge.json();
    assertEquals(body.error, 'request body too large');
  }
});

Deno.test('readJsonWithLimit — rejects a Content-Length lie (header small, body large)', async () => {
  // Header says 16 bytes, body actually streams 8 KB. The fast-path
  // accepts the header; the streaming reader must still catch the
  // overflow — Content-Length is advisory, not enforced by the
  // runtime.
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array(8 * 1024).fill(0x20));
      controller.close();
    },
  });
  const req = new Request('http://x.test/', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'content-length': '16',
    },
    body: stream,
  });
  const out = await readJsonWithLimit(req, 4096);
  assertStrictEquals('tooLarge' in out, true);
});

Deno.test('readJsonWithLimit — empty body returns body undefined, not 413', async () => {
  // GET-shaped requests with no body must not error — clip-public-track
  // tolerates them.
  const req = new Request('http://x.test/', { method: 'POST' });
  const out = await readJsonWithLimit(req, 4096);
  assertStrictEquals('body' in out, true);
});

// ─────────────── readTextWithLimit ───────────────
//
// Used by webhook handlers (revenuecat-webhook + strava-webhook) where
// the HMAC must run on the wire-format text — a parse-and-reserialise
// would not round-trip whitespace + key ordering.

Deno.test('readTextWithLimit — accepts a small body and returns text verbatim', async () => {
  const req = new Request('http://x.test/', {
    method: 'POST',
    body: '  {  "a":1  }  ',
  });
  const out = await readTextWithLimit(req, 4096);
  assertStrictEquals('text' in out, true);
  if ('text' in out) {
    // Whitespace + ordering preserved — that's the whole point.
    assertEquals(out.text, '  {  "a":1  }  ');
  }
});

Deno.test('readTextWithLimit — rejects a chunked-transfer body over the cap', async () => {
  const req = reqWithChunkedBody(8 * 1024);
  const out = await readTextWithLimit(req, 4096);
  assertStrictEquals('tooLarge' in out, true);
  if ('tooLarge' in out) {
    assertStrictEquals(out.tooLarge.status, 413);
  }
});

// ── discardBody ────────────────────────────────────────────────────
//
// Used by header-only / cron Edge Functions (refresh-tokens) that take
// no body input. The pre-fix shape held the request stream open until
// the runtime timeout when a caller POSTed a chunked body — slow-loris
// DoS vector against the function host. The fix cancels the readable
// stream at the start of the handler so the runtime + client see "no
// more bytes please" immediately.

// `bodyUsed` is the discriminator, and it is the only one that answers
// synchronously and in one state: `cancel()` disturbs the stream the moment it
// is called, so a helper that did nothing leaves it false. Reading the stream
// instead was what made the first of these vacuous — a cancelled stream may
// return `{done: true}` or throw, so the read was wrapped in a `try/catch`
// that swallowed the AssertionError along with the throw it was written for,
// and the test passed whether or not anything had been cancelled.
function bodied(): Request {
  return new Request('http://x.test/', { method: 'POST', body: 'should-not-be-read' });
}

Deno.test('discardBody — cancels the body stream so no bytes are read', () => {
  const req = bodied();
  const control = bodied();
  discardBody(req);
  assertStrictEquals(req.bodyUsed, true, 'the body stream was never disturbed');
  assertStrictEquals(control.bodyUsed, false, 'an untouched request must read false');
});

Deno.test('discardBody — no body present is a clean no-op', () => {
  // GET / HEAD / OPTIONS requests don't carry a body; the helper
  // must not throw when req.body is null.
  const req = new Request('http://x.test/', { method: 'GET' });
  assertStrictEquals(req.body, null, 'the fixture must actually be bodyless');
  discardBody(req);
  // Not throwing is the whole claim here, and an absent throw is also what a
  // helper that does nothing produces — so the claim is only worth anything
  // beside a positive control proving this same helper does act when there IS
  // a body.
  const control = bodied();
  discardBody(control);
  assertStrictEquals(control.bodyUsed, true, 'the control body was never disturbed');
});

Deno.test('discardBody — second call on an already-cancelled body does not throw', () => {
  // The helper swallows the "already cancelled" rejection so it can
  // be called defensively (e.g. once at the top of the handler, again
  // in a finally block).
  const req = bodied();
  discardBody(req);
  discardBody(req);
  assertStrictEquals(req.bodyUsed, true, 'the first cancel must still have taken');
});
