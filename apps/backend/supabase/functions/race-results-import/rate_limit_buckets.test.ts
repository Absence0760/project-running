// A credential PROBE and a real IMPORT are two different costs, and this
// function charged them to one bucket until decisions § 1041.
//
// A probe reads env vars and returns; an import spends OUR per-application
// RunSignUp / ChronoTrack credential and writes the caller's `runs`. The
// settings screen probes once per credential-gated leg it offers, so with one
// bucket a runner who opened Settings a few times in an hour lost the ability
// to import a result at all — and since § 1007 an exhausted bucket answers 429,
// which both clients grade as "provider unavailable", so the failure is silent
// and total rather than a limit anyone can see.
//
// Source-level rather than behavioural because the limiter needs a database:
// the claim is about which bucket the code selects, which is readable.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

function limits(bucket: string): [number, number] {
  const re = new RegExp(
    `'${bucket.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}',\\s*(\\d+),\\s*(\\d+),`,
  );
  const m = SRC.match(re);
  assert(m, `no checkRateLimitTiered call for the ${bucket} bucket`);
  return [Number(m[1]), Number(m[2])];
}

Deno.test('the bucket is selected on the probe flag', () => {
  assert(
    /const denied = isProbe\s*\?/.test(SRC),
    'the function no longer selects its rate-limit bucket on the probe flag — ' +
      're-anchor this guard rather than deleting it',
  );
});

Deno.test('a probe is charged to a bucket of its own, more generous than the import one', () => {
  const [probeFree, probePro] = limits('race-results-import:probe');
  const [importFree, importPro] = limits('race-results-import');
  assert(
    probeFree > importFree,
    `the probe bucket (${probeFree}/h free) is no more generous than the import ` +
      `bucket (${importFree}/h), so opening Settings still spends imports`,
  );
  assert(
    probePro > importPro,
    `the Pro probe bucket (${probePro}/h) is no more generous than the import ` +
      `bucket (${importPro}/h)`,
  );
});

Deno.test('both buckets fail closed', () => {
  // Falling open on an RPC blip drops the only bound on how often one account
  // can drive either path (§ 974), and the probe path is the cheaper one to
  // hammer.
  assertEquals(SRC.match(/failClosed: true/g)?.length, 2);
});
