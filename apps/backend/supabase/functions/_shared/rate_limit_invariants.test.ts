/// What the rate-limit helper SENDS, and what it does with an answer it did
/// not expect.
///
/// The sibling suite pins the response shape thoroughly and the bucket key
/// against header spoofing. What neither covers is the request: every existing
/// case supplies `max` and `windowSeconds` and then asserts nothing about them,
/// so a helper that passed its own constants — one bucket for every caller, or
/// one ceiling for every bucket — satisfies the whole file. `check_rate_limit`
/// keys its counter by bucket alone, so a bucket sent wrong is one caller's
/// traffic throttling another's.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/rate_limit_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { checkRateLimit, checkRateLimitTiered, ipBucketKey, trustedIpHeaderName } from './rate_limit.ts';

interface Call {
  name: string;
  args: Record<string, unknown>;
}

function recordingSupabase(result: { data: unknown; error: unknown }) {
  const calls: Call[] = [];
  // deno-lint-ignore no-explicit-any
  const client: any = {
    rpc: (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args });
      return Promise.resolve(result);
    },
  };
  return { client, calls };
}

const ALLOWED = { data: [{ allowed: true, retry_after_seconds: 0 }], error: null };
const DENIED = { data: [{ allowed: false, retry_after_seconds: 42 }], error: null };

Deno.test('checkRateLimit — the caller\'s bucket, ceiling and window reach the RPC verbatim', () => {
  const { client, calls } = recordingSupabase(ALLOWED);
  return checkRateLimit(client, 'u-1', 'parkrun-import', 4, 3600).then(() => {
    assertEquals(calls.length, 1);
    assertEquals(calls[0].name, 'check_rate_limit');
    assertEquals(calls[0].args, {
      p_user_id: 'u-1',
      p_bucket: 'parkrun-import',
      p_max: 4,
      p_window_seconds: 3600,
    });
  });
});

Deno.test('checkRateLimit — two callers do not collapse onto one bucket', () => {
  // Stated as a difference rather than as an equality: an equality between two
  // of the helper's own outputs is satisfied by a helper that sends a constant,
  // which is exactly the anti-spoofing shape § 788 found four of.
  const { client, calls } = recordingSupabase(ALLOWED);
  return checkRateLimit(client, 'u-1', 'a', 4, 3600)
    .then(() => checkRateLimit(client, 'u-2', 'b', 9, 60))
    .then(() => {
      assertEquals(calls.length, 2);
      assert(calls[0].args.p_user_id !== calls[1].args.p_user_id);
      assert(calls[0].args.p_bucket !== calls[1].args.p_bucket);
      assert(calls[0].args.p_max !== calls[1].args.p_max);
      assert(calls[0].args.p_window_seconds !== calls[1].args.p_window_seconds);
    });
});

Deno.test('checkRateLimitTiered — both ceilings and the window reach its own RPC', () => {
  const { client, calls } = recordingSupabase(ALLOWED);
  return checkRateLimitTiered(client, 'u-1', 'strava-import:sync', 4, 16, 3600).then(() => {
    assertEquals(calls.length, 1);
    assertEquals(calls[0].name, 'check_rate_limit_tiered');
    assertEquals(calls[0].args, {
      p_user_id: 'u-1',
      p_bucket: 'strava-import:sync',
      p_free_max: 4,
      p_pro_max: 16,
      p_window_seconds: 3600,
    });
  });
});

Deno.test('checkRateLimitTiered — the free ceiling is never sent as the pro one', () => {
  // They are adjacent numeric arguments of the same type, so a transposition
  // typechecks and gives every free caller the pro allowance.
  const { client, calls } = recordingSupabase(ALLOWED);
  return checkRateLimitTiered(client, 'u-1', 'b', 4, 16, 3600).then(() => {
    assertEquals(calls[0].args.p_free_max, 4);
    assertEquals(calls[0].args.p_pro_max, 16);
  });
});

Deno.test('checkRateLimit — a row that does not say `allowed` is a denial, not a pass', async () => {
  // `allowed` is read as a truthy test, so the direction of an unreadable row
  // is the whole safety property: a missing, null or non-boolean field must
  // land on the 429 rather than through the gate.
  const withheld: unknown[] = [undefined, null, false, 0, '', Number.NaN];
  for (const allowed of withheld) {
    const { client } = recordingSupabase({
      data: [{ allowed, retry_after_seconds: 5 }],
      error: null,
    });
    const r = await checkRateLimit(client, 'u-1', 'b', 4, 3600);
    assert(r !== null, `allowed=${String(allowed)} let the request through`);
    assertEquals(r.status, 429);
  }
});

Deno.test('checkRateLimit — a truthy non-boolean `allowed` still lets the request through', async () => {
  // The complement of the case above, so "denies everything" is not what makes
  // that one pass.
  const { client } = recordingSupabase({
    data: [{ allowed: true, retry_after_seconds: 0 }],
    error: null,
  });
  assertEquals(await checkRateLimit(client, 'u-1', 'b', 4, 3600), null);
});

Deno.test('checkRateLimit — the header and the body always name the same wait', async () => {
  // A client reads one or the other. Two figures that disagree is a client
  // backing off for the wrong length of time, and only a comparison between
  // them catches it.
  for (const raw of [1, 2, 42, 900, 3599, 0, -1, -900, 4.9, '7', null, undefined]) {
    const { client } = recordingSupabase({
      data: [{ allowed: false, retry_after_seconds: raw }],
      error: null,
    });
    const r = await checkRateLimit(client, 'u-1', 'b', 4, 3600);
    assert(r !== null);
    const body = await r.json();
    assertEquals(r.headers.get('Retry-After'), String(body.retry_after_seconds), String(raw));
    assert(Number.isInteger(body.retry_after_seconds), `${raw} produced ${body.retry_after_seconds}`);
    assert(body.retry_after_seconds >= 1, `${raw} produced ${body.retry_after_seconds}`);
  }
});

Deno.test('checkRateLimitTiered — its denial carries the same floor and agreement', async () => {
  for (const raw of [0, -5, 4.9, 900]) {
    const { client } = recordingSupabase({
      data: [{ allowed: false, retry_after_seconds: raw, tier: 'free' }],
      error: null,
    });
    const r = await checkRateLimitTiered(client, 'u-1', 'b', 4, 16, 3600);
    assert(r !== null);
    const body = await r.json();
    assertEquals(r.headers.get('Retry-After'), String(body.retry_after_seconds), String(raw));
    assert(body.retry_after_seconds >= 1);
    assertEquals(body.tier, 'free');
  }
});

Deno.test('checkRateLimit — an unusable RPC result takes the posture, not the happy path', async () => {
  const unusable: Array<{ data: unknown; error: unknown }> = [
    { data: null, error: { code: '42501', message: 'denied' } },
    { data: [], error: null },
    { data: null, error: null },
    { data: {}, error: null },
    { data: 'ok', error: null },
    { data: [{ allowed: true }], error: { code: 'PGRST301', message: 'jwt expired' } },
  ];
  for (const result of unusable) {
    const open = await checkRateLimit(recordingSupabase(result).client, 'u-1', 'b', 4, 3600);
    assertEquals(open, null, `fail-open on ${JSON.stringify(result.data)}`);
    const closed = await checkRateLimit(recordingSupabase(result).client, 'u-1', 'b', 4, 3600, {
      failClosed: true,
    });
    assert(closed !== null, `fail-closed on ${JSON.stringify(result.data)}`);
    assertEquals(closed.status, 503);
    assertEquals(closed.headers.get('Retry-After'), '60');
    const body = await closed.json();
    assertEquals(body.error, 'rate_limit_unavailable');
    assertEquals(body.bucket, 'b');
  }
});

Deno.test('checkRateLimit — the posture is opt-in, so an omitted flag lets traffic through', async () => {
  // `failClosed` gates a 503 on the paths where letting traffic through is
  // worse than a false denial — delete-account, the heavy export, an OAuth code
  // exchange. Every other caller must be unaffected by its existence, so the
  // three ways of not asking for it have to agree with each other.
  const result = { data: [], error: null };
  for (const opts of [undefined, {}, { failClosed: false }] as const) {
    assertEquals(
      await checkRateLimit(recordingSupabase(result).client, 'u-1', 'b', 4, 3600, opts),
      null,
      JSON.stringify(opts),
    );
  }
  const closed = await checkRateLimit(recordingSupabase(result).client, 'u-1', 'b', 4, 3600, {
    failClosed: true,
  });
  assert(closed !== null);
});

Deno.test('checkRateLimit — the RPC is called exactly once per check', async () => {
  // A helper that retried would spend the caller's own window on the retry,
  // since the counter increments inside the RPC.
  for (const result of [ALLOWED, DENIED, { data: [], error: null }]) {
    const { client, calls } = recordingSupabase(result);
    await checkRateLimit(client, 'u-1', 'b', 4, 3600);
    assertEquals(calls.length, 1, JSON.stringify(result.data));
  }
});

const req = (headers: Record<string, string>) =>
  new Request('http://x.test/', { method: 'POST', headers });

Deno.test('ipBucketKey — a known-answer vector, so the salt and the encoding are pinned too', async () => {
  // Every other assertion on this function compares two of its own outputs,
  // which a constant satisfies (§ 788). A literal answer fixes the digest, the
  // `anon-rate-limit-v1:` salt and the hex slicing at once — and moving the
  // salt silently re-buckets every anonymous caller, resetting every live
  // window, which is a change that should cost a test edit.
  assertEquals(
    await ipBucketKey(req({ 'cf-connecting-ip': '203.0.113.7' })),
    'ea8e262c-5f89-8063-bd41-9d52a8b1a538',
  );
  assertEquals(
    await ipBucketKey(req({ 'cf-connecting-ip': '2001:db8::1' })),
    '58a1c4af-7383-8ab0-40db-e5624edddd45',
  );
  // The unknown bucket has a literal answer too, so the shared-bucket fallback
  // is a fixed name rather than whatever the last refactor left behind.
  assertEquals(await ipBucketKey(req({})), '5483c07e-8118-8c6d-3b17-3b089b9eccab');
});

Deno.test('ipBucketKey — the unknown bucket is one bucket, and a real IP is not in it', async () => {
  const unknown = await ipBucketKey(req({}));
  const collapsing: Array<Record<string, string>> = [
    { 'x-forwarded-for': '1.1.1.1' },
    { 'x-real-ip': '1.1.1.1' },
    { 'cf-connecting-ip': '1.1.1.1, 2.2.2.2' },
    { 'cf-connecting-ip': 'not-an-ip' },
    { 'cf-connecting-ip': '' },
    { 'cf-connecting-ip': '   ' },
    { 'cf-connecting-ip': '1.1.1.1 2.2.2.2' },
    { 'cf-connecting-ip': `${'a'.repeat(46)}` },
  ];
  for (const headers of collapsing) {
    assertEquals(await ipBucketKey(req(headers)), unknown, JSON.stringify(headers));
  }
  // And the positive control: a trusted header really does establish a bucket
  // of its own, so "everything collapses" is not what makes the above pass.
  assert(await ipBucketKey(req({ 'cf-connecting-ip': '1.1.1.1' })) !== unknown);
});

Deno.test('ipBucketKey — an IPv6 literal is accepted and case-folded, not discarded', async () => {
  const lower = await ipBucketKey(req({ 'cf-connecting-ip': '2001:db8::1' }));
  const upper = await ipBucketKey(req({ 'cf-connecting-ip': '2001:DB8::1' }));
  const padded = await ipBucketKey(req({ 'cf-connecting-ip': '  2001:db8::1  ' }));
  assertEquals(lower, upper);
  assertEquals(lower, padded);
  assert(lower !== await ipBucketKey(req({})));
  assert(lower !== await ipBucketKey(req({ 'cf-connecting-ip': '2001:db8::2' })));
});

Deno.test('ipBucketKey — the length bound is 45 characters, the longest IPv6 text form', async () => {
  const unknown = await ipBucketKey(req({}));
  // The bound is named for this address, so it is this address the case is
  // measured with. It used to be measured with 45 letters, which the value
  // check now rejects for not being an address at all — and which the old
  // hex-only class had admitted precisely because it could not have admitted
  // the real thing (the IPv4-mapped tail carries dots).
  const at45 = 'ffff:ffff:ffff:ffff:ffff:ffff:255.255.255.255';
  assertEquals(at45.length, 45);
  assert(await ipBucketKey(req({ 'cf-connecting-ip': at45 })) !== unknown);
  const at46 = `f${at45}`;
  assertEquals(at46.length, 46);
  assertEquals(await ipBucketKey(req({ 'cf-connecting-ip': at46 })), unknown);
});

Deno.test('ipBucketKey — a value that is not an address does not get a window of its own', async () => {
  // The point of the trusted-header design is that the caller cannot pick
  // their own bucket. A hex-only class made every bare word an address, so
  // any token a caller sent minted a fresh window — a rate limit that resets
  // on demand is not one. Each of these collapses into the shared bucket.
  const unknown = await ipBucketKey(req({}));
  for (
    const value of [
      'a',
      'abcdef',
      'deadbeef',
      'f'.repeat(45),
      '1234',
      '...',
      '1.2.3',
      '1.2.3.4.5',
    ]
  ) {
    assertEquals(
      await ipBucketKey(req({ 'cf-connecting-ip': value })),
      unknown,
      value,
    );
  }
  // The positive controls, so "everything collapses" is not what makes the
  // above pass: both address families still get a bucket, and two different
  // addresses get two different buckets.
  const v4 = await ipBucketKey(req({ 'cf-connecting-ip': '1.1.1.1' }));
  const v6 = await ipBucketKey(req({ 'cf-connecting-ip': '::ffff:1.1.1.1' }));
  assert(v4 !== unknown && v6 !== unknown && v4 !== v6);
});

Deno.test('ipBucketKey — every answer is a UUID with the literal 8 version nibble', async () => {
  const shaped = /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const shapes: Array<Record<string, string>> = [
    {},
    { 'cf-connecting-ip': '1.1.1.1' },
    { 'cf-connecting-ip': '::1' },
  ];
  for (const headers of shapes) {
    const key = await ipBucketKey(req(headers));
    assert(shaped.test(key), `${JSON.stringify(headers)} -> ${key}`);
  }
});

Deno.test('trustedIpHeaderName — the override is normalised, and a blank one is not an override', async () => {
  const previous = Deno.env.get('TRUSTED_CLIENT_IP_HEADER');
  try {
    Deno.env.delete('TRUSTED_CLIENT_IP_HEADER');
    assertEquals(trustedIpHeaderName(), 'cf-connecting-ip');
    for (const blank of ['', '   ', '\t']) {
      Deno.env.set('TRUSTED_CLIENT_IP_HEADER', blank);
      assertEquals(trustedIpHeaderName(), 'cf-connecting-ip', JSON.stringify(blank));
    }
    Deno.env.set('TRUSTED_CLIENT_IP_HEADER', '  X-Real-IP  ');
    assertEquals(trustedIpHeaderName(), 'x-real-ip');
    // And the override is what the key actually reads, not just what the name
    // function reports: a self-hosted deployment behind nginx depends on it.
    const viaOverride = await ipBucketKey(req({ 'x-real-ip': '1.1.1.1' }));
    Deno.env.delete('TRUSTED_CLIENT_IP_HEADER');
    assertEquals(viaOverride, await ipBucketKey(req({ 'cf-connecting-ip': '1.1.1.1' })));
    assertEquals(await ipBucketKey(req({ 'x-real-ip': '1.1.1.1' })), await ipBucketKey(req({})));
  } finally {
    if (previous === undefined) Deno.env.delete('TRUSTED_CLIENT_IP_HEADER');
    else Deno.env.set('TRUSTED_CLIENT_IP_HEADER', previous);
  }
});
