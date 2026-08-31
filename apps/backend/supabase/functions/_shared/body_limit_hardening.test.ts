/// The body readers at their boundaries, and on the bodies a caller would only
/// send on purpose.
///
/// The sibling suite covers the header fast path, the chunked bypass and a
/// Content-Length lie. What it does not reach is the cap's own edge (is the
/// limit inclusive?), the 400 a malformed body earns — which is returned in the
/// SAME `tooLarge` field as a 413, so a caller that reads the status rather
/// than the field would report "too large" for a typo — and the fact that the
/// cap counts UTF-8 BYTES, which is the only measure that bounds an allocation.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/body_limit_hardening.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  discardBody,
  enforceBodyLimit,
  readJsonWithLimit,
  readTextWithLimit,
} from './body_limit.ts';

/// A request whose body arrives as a stream with NO Content-Length, so only the
/// streamed reader can bound it. That is the shape the header fast path cannot
/// see, and the one an attacker would choose.
function chunked(bytes: Uint8Array, chunkSize = 8): Request {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (let i = 0; i < bytes.length; i += chunkSize) {
        controller.enqueue(bytes.subarray(i, Math.min(i + chunkSize, bytes.length)));
      }
      controller.close();
    },
  });
  return new Request('http://x.test/', { method: 'POST', body: stream });
}

const utf8 = (s: string) => new TextEncoder().encode(s);

Deno.test('readJsonWithLimit — the cap is inclusive, so a body of exactly the limit is read', async () => {
  const body = utf8('{"a":"bb"}');
  assertEquals(body.length, 10);
  const ok = await readJsonWithLimit<{ a: string }>(chunked(body), 10);
  assert(!('tooLarge' in ok), 'exactly at the cap must be accepted');
  assertEquals(ok.body.a, 'bb');
  const over = await readJsonWithLimit(chunked(body), 9);
  assert('tooLarge' in over);
  assertEquals(over.tooLarge.status, 413);
});

Deno.test('readTextWithLimit — the same inclusive edge, and the text is byte-exact', async () => {
  const raw = '{"a":"bb"}';
  const ok = await readTextWithLimit(chunked(utf8(raw)), 10);
  assert(!('tooLarge' in ok));
  assertEquals(ok.text, raw, 'the HMAC runs on this, so it must be the wire text');
  const over = await readTextWithLimit(chunked(utf8(raw)), 9);
  assert('tooLarge' in over);
  assertEquals(over.tooLarge.status, 413);
});

Deno.test('the cap counts UTF-8 bytes, not characters — which is what bounds the allocation', async () => {
  // Ten astral-plane characters are 40 bytes. A reader counting characters
  // would let a caller through at four times the budget it was given, which is
  // the whole point of having one.
  const emoji = '\u{1F600}'.repeat(10);
  const raw = JSON.stringify({ m: emoji });
  const bytes = utf8(raw);
  assert(bytes.length > raw.length, 'the byte count really does exceed the char count');
  const overByBytes = await readTextWithLimit(chunked(bytes), raw.length);
  assert('tooLarge' in overByBytes, 'a char-counting cap would have admitted this');
  const ok = await readTextWithLimit(chunked(bytes), bytes.length);
  assert(!('tooLarge' in ok));
  assertEquals(ok.text, raw, 'and the multi-byte characters survive the decode');
});

Deno.test('readJsonWithLimit — a body split across many chunks is reassembled in order', async () => {
  // The reader accumulates chunks and copies them into one buffer at the end.
  // An offset bug there produces a body that is the right LENGTH and the wrong
  // content, which JSON.parse would then reject as invalid — reported as a 400
  // the caller cannot act on.
  const payload = { message: 'a'.repeat(500), n: 12345, nested: { deep: [1, 2, 3] } };
  const raw = JSON.stringify(payload);
  const parsed = await readJsonWithLimit<typeof payload>(chunked(utf8(raw), 1), 4096);
  assert(!('tooLarge' in parsed));
  assertEquals(parsed.body, payload);
});

Deno.test('readJsonWithLimit — a malformed body is a 400, and never a silent undefined', async () => {
  // The 400 travels in the same `tooLarge` field as the 413, which every caller
  // returns verbatim. What must not happen is a parse failure producing a
  // `body` the handler then reads keys off.
  const malformed = ['{', '{"a":}', 'not json', '[1,2', '{"a":1}{"b":2}', ' '];
  for (const raw of malformed) {
    const r = await readJsonWithLimit(chunked(utf8(raw)), 4096);
    assert('tooLarge' in r, JSON.stringify(raw));
    assertEquals(r.tooLarge.status, 400, JSON.stringify(raw));
    assertEquals((await r.tooLarge.json()).error, 'invalid_json');
  }
});

Deno.test('readJsonWithLimit — a JSON scalar parses, because the shape is the caller\'s business', async () => {
  // The complement of the case above: only genuinely unparseable text earns the
  // 400. A reader that rejected everything would satisfy every malformed case.
  for (const raw of ['null', 'true', '42', '"s"', '[]', '{}']) {
    const r = await readJsonWithLimit(chunked(utf8(raw)), 4096);
    assert(!('tooLarge' in r), raw);
    assertEquals(r.body, JSON.parse(raw), raw);
  }
});

Deno.test('readJsonWithLimit — an empty body is undefined, never a 413 or a 400', async () => {
  const noBody = new Request('http://x.test/', { method: 'POST' });
  const r = await readJsonWithLimit(noBody, 4096);
  assert(!('tooLarge' in r));
  assertEquals(r.body, undefined);
  const emptyStream = await readJsonWithLimit(chunked(new Uint8Array(0)), 4096);
  assert(!('tooLarge' in emptyStream));
  assertEquals(emptyStream.body, undefined);
  const emptyText = await readTextWithLimit(chunked(new Uint8Array(0)), 4096);
  assert(!('tooLarge' in emptyText));
  assertEquals(emptyText.text, '');
});

Deno.test('readJsonWithLimit — an oversize stream is cancelled, not drained', async () => {
  // The bytes past the cap must never land in the process. A reader that read
  // to the end and then answered 413 would leave the stream exhausted rather
  // than cancelled, which is the allocation the cap exists to prevent.
  let cancelled = false;
  let pulled = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulled++;
      controller.enqueue(new Uint8Array(1024));
      if (pulled > 1000) controller.close();
    },
    cancel() {
      cancelled = true;
    },
  });
  const req = new Request('http://x.test/', { method: 'POST', body: stream });
  const r = await readJsonWithLimit(req, 4096);
  assert('tooLarge' in r);
  assertEquals(r.tooLarge.status, 413);
  assert(cancelled, 'the source must be cancelled once the cap is passed');
  assert(pulled < 100, `stopped early, pulled ${pulled}`);
});

Deno.test('enforceBodyLimit — an honest oversize header is refused before a byte arrives', async () => {
  const req = new Request('http://x.test/', {
    method: 'POST',
    body: 'x'.repeat(100),
    headers: { 'content-length': '100' },
  });
  const refused = enforceBodyLimit(req, 99);
  assert(refused !== null);
  assertEquals(refused.status, 413);
  assertEquals((await refused.json()).max_bytes, 99);
  assertEquals(req.bodyUsed, false, 'nothing was read to decide this');
});

Deno.test('enforceBodyLimit — the header edge is inclusive, matching the streamed reader', async () => {
  // The two paths have to agree, or a caller with a Content-Length is held to a
  // different limit than one without.
  const at = (declared: number, limit: number) =>
    enforceBodyLimit(
      new Request('http://x.test/', {
        method: 'POST',
        body: 'x'.repeat(declared),
        headers: { 'content-length': String(declared) },
      }),
      limit,
    );
  assertEquals(at(100, 100), null, 'exactly the cap passes the header check');
  assert(at(101, 100) !== null);
  const streamed = await readTextWithLimit(chunked(utf8('x'.repeat(100))), 100);
  assert(!('tooLarge' in streamed), 'and exactly the cap passes the streamed one');
});

Deno.test('enforceBodyLimit — a header it cannot believe defers to the streamed reader', async () => {
  // A missing, negative or non-numeric Content-Length is not a refusal here:
  // the fast path exists to save work, and the bound is the streamed reader's.
  // Answering 413 on an unparseable header would refuse legitimate chunked
  // callers; answering 200 without the streamed reader would be the bypass.
  for (const header of ['abc', '-1', '', ' ', 'Infinity', '1e9']) {
    const req = new Request('http://x.test/', {
      method: 'POST',
      body: 'x'.repeat(10),
      headers: { 'content-length': header },
    });
    assertEquals(enforceBodyLimit(req, 5), null, JSON.stringify(header));
  }
  // And the streamed reader really does catch what the header did not.
  const guarded = await readTextWithLimit(chunked(utf8('x'.repeat(10))), 5);
  assert('tooLarge' in guarded);
  assertEquals(guarded.tooLarge.status, 413);
});

Deno.test('discardBody — the body is given up without being read', () => {
  // `cancel()` marks the request's body used synchronously, which is the only
  // observable the helper has: it never returns anything.
  const req = new Request('http://x.test/', { method: 'POST', body: 'x'.repeat(100) });
  assertEquals(req.bodyUsed, false);
  discardBody(req);
  assertEquals(req.bodyUsed, true);
  // Idempotent — a second call on an already-cancelled body must not throw.
  discardBody(req);
  assertEquals(req.bodyUsed, true);
});
