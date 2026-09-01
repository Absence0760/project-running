/// The envelope every one of the sixteen Edge Functions is wrapped in.
///
/// `withSentry` had no test of any kind, and it is the single piece of code
/// on the response path of every function in the tree. Two of its properties
/// are load-bearing and neither was stated anywhere: a handler's own Response
/// must reach the caller unaltered (including a deliberate 4xx, which is an
/// answer and not a failure), and a THROWN error must not — the message it
/// carries is the one place a PostgREST `details` string, a Storage path or a
/// row value would reach an anonymous caller.
///
/// `SENTRY_DSN` is unset here, so the capture side is inert and the assertions
/// are about the envelope alone. That is the shape every local run and every
/// CI job already executes under.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/sentry.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { withSentry } from './sentry.ts';

const post = () => new Request('http://127.0.0.1/', { method: 'POST', body: '{}' });

function captureConsoleError(): { lines: string[]; restore: () => void } {
  const lines: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    lines.push(args.map((a) => String(a)).join(' '));
  };
  return { lines, restore: () => { console.error = original; } };
}

Deno.test('a handler that answers has its answer passed through untouched', async () => {
  const body = JSON.stringify({ points: [1, 2, 3] });
  const wrapped = withSentry('probe', () =>
    new Response(body, {
      status: 207,
      headers: { 'Content-Type': 'application/json', 'X-Probe': 'kept' },
    }));
  const res = await wrapped(post());
  assertEquals(res.status, 207);
  assertEquals(res.headers.get('X-Probe'), 'kept');
  assertEquals(res.headers.get('Content-Type'), 'application/json');
  assertEquals(await res.text(), body);
});

Deno.test('a deliberate refusal is an answer, not a failure to convert into 500', async () => {
  // Every handler in this tree answers 400 / 401 / 403 / 404 / 409 / 413 /
  // 429 / 502 / 503 on its own fail-closed paths. An envelope that treated a
  // non-2xx as an error would collapse all of them into one opaque 500 and
  // destroy every refusal the rest of this suite measures.
  for (const status of [400, 401, 403, 404, 409, 413, 429, 502, 503]) {
    const wrapped = withSentry('probe', () =>
      Response.json({ error: 'refused' }, { status }));
    const res = await wrapped(post());
    assertEquals(res.status, status);
    assertEquals((await res.json()).error, 'refused');
  }
});

Deno.test('a thrown error becomes a 500 that says nothing about what threw', async () => {
  // The message is the leak surface: a PostgREST failure carries the
  // offending row in `details`, a Storage failure carries the owner-scoped
  // path, and `clip-public-track` reaches this envelope on an ANONYMOUS
  // request. The body has to be a constant.
  const { lines, restore } = captureConsoleError();
  try {
    const wrapped = withSentry('probe', () => {
      throw new Error('duplicate key value violates unique constraint (email)=(a@b.com)');
    });
    const res = await wrapped(post());
    assertEquals(res.status, 500);
    assertEquals(res.headers.get('Content-Type'), 'application/json');
    const text = await res.text();
    assertEquals(JSON.parse(text), { error: 'internal_error' });
    assert(!text.includes('a@b.com'), 'the thrown message reached the caller');
    assert(!text.includes('probe'), 'the function name reached the caller');
  } finally {
    restore();
  }
  // It is not swallowed either: the operator still gets it, tagged with the
  // function that raised it. A silent 500 is the other failure mode.
  assertEquals(lines.length, 1);
  assert(lines[0].startsWith('[probe] unhandled:'), lines[0]);
  assert(lines[0].includes('a@b.com'), 'the operator log must keep the message');
});

Deno.test('a thrown non-Error is handled the same way, not re-thrown', async () => {
  // `throw 'string'` and a rejected promise carrying a plain object both
  // reach here; an envelope that assumed `err instanceof Error` would throw
  // inside its own catch and the platform would answer with no body at all.
  const { lines, restore } = captureConsoleError();
  try {
    for (const thrown of ['plain string', { code: '23505' }, null, undefined, 42]) {
      const wrapped = withSentry('probe', () => {
        throw thrown;
      });
      const res = await wrapped(post());
      assertEquals(res.status, 500, String(thrown));
      assertEquals(await res.json(), { error: 'internal_error' });
    }
  } finally {
    restore();
  }
  assertEquals(lines.length, 5);
});

Deno.test('a rejected promise is caught, and so is a synchronous throw', async () => {
  // The handler signature admits both `Promise<Response>` and `Response`, so
  // the envelope has to await inside its own try — a `return handler(req)`
  // without the await catches the sync case and leaks the async one.
  const { lines, restore } = captureConsoleError();
  try {
    const asyncThrow = withSentry('probe', () => Promise.reject(new Error('async boom')));
    assertEquals((await asyncThrow(post())).status, 500);
    const syncThrow = withSentry('probe', () => {
      throw new Error('sync boom');
    });
    assertEquals((await syncThrow(post())).status, 500);
    // And the sync SUCCESS path still returns a real Response rather than a
    // promise the platform would serialise as `{}`.
    const syncOk = withSentry('probe', () => new Response('sync ok'));
    const res = await syncOk(post());
    assert(res instanceof Response);
    assertEquals(await res.text(), 'sync ok');
  } finally {
    restore();
  }
  assertEquals(lines.length, 2);
});

Deno.test('the wrapper hands the request through unchanged', async () => {
  // Several handlers read the body, the method and the Authorization header
  // off the request they are given. An envelope that consumed or rebuilt it
  // would break the HMAC path, which must see the RAW bytes.
  let seen: { method: string; auth: string | null; body: string } | null = null;
  const wrapped = withSentry('probe', async (req) => {
    seen = {
      method: req.method,
      auth: req.headers.get('Authorization'),
      body: await req.text(),
    };
    return new Response('ok');
  });
  const raw = '{"id":"evt_1",  "type":"x"}';
  await wrapped(
    new Request('http://127.0.0.1/', {
      method: 'POST',
      headers: { Authorization: 'Bearer t' },
      body: raw,
    }),
  );
  assertEquals(seen, { method: 'POST', auth: 'Bearer t', body: raw });
});
