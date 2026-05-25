import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.105.1';
import { checkRateLimit, ipBucketKey } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';
import { isValidUuid } from '../_shared/webhook_security.ts';

// Serves a privacy-zone-clipped track for a public run. Replaces
// direct Storage download for non-owner viewers (audit/storage High,
// migration 20260619_001 dropped the public-runs Storage policy).
//
// Flow:
//   1. Authenticate the caller (anon JWT or user JWT — both fine; the
//      user-scoped client respects RLS so private runs return null
//      for non-owners).
//   2. Look up the run row via the caller's JWT. RLS gates this;
//      private rows get null and we 404.
//   3. Download the gzipped track via the service-role client (the
//      anon Storage policy was just removed).
//   4. If the caller is not the owner, route the points through
//      clip_track_for_user. Owners receive the unclipped track.
//   5. Return the points as JSON.

serve(withSentry('clip-public-track', async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // Body is just `{ run_id: uuid }` — 1 KB is plenty. The streamed
  // reader closes the chunked-transfer-encoding bypass that the bare
  // header check left open.
  const guarded = await readJsonWithLimit<{ run_id?: unknown }>(req, 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return Response.json({ error: 'missing authorization' }, { status: 401 });
  }

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  const callerId = user?.id ?? null;

  // Validate body BEFORE rate-limiting so malformed requests don't
  // drain the IP bucket. An anon attacker who fires 60 empty POSTs in
  // quick succession would otherwise lock everyone behind the same
  // shared NAT out for the rest of the hour.
  const body = (guarded.body ?? {}) as { run_id?: unknown };
  const runId = body.run_id;
  if (typeof runId !== 'string' || runId.length === 0) {
    return Response.json({ error: 'run_id required' }, { status: 400 });
  }
  // audit/edge-functions (2026-05-25): reject anything that isn't a
  // UUID before it reaches the PostgREST query. PostgREST converts
  // a non-UUID into a 22P02 (invalid_input_syntax) which surfaces
  // as a 500 / Sentry event and still burns the rate-limit slot.
  if (!isValidUuid(runId)) {
    return Response.json({ error: 'run_id must be a UUID' }, { status: 400 });
  }

  // Rate-limit before doing any DB / Storage work. Authenticated
  // callers get their own per-user bucket via the existing user-id
  // path. Anon callers share a per-IP bucket — they're the abuse
  // surface (each call is 1 PostgREST query + up to 25 MB Storage
  // download + a clip walk over up to 50k points). The admin client
  // is required for the anon path because the user-context guard
  // from migration 20260616_001 rejects synthetic IP-derived keys.
  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  // Fail-closed because the anon path is the abuse surface and a DB
  // blip on the rate-limit RPC would otherwise remove the only IP-
  // level guard. Each request can drive 1 PostgREST query + up to
  // 5 MB Storage download + a 50k-point clip walk; the failure mode
  // we want is a 503 retry, not unbounded throughput.
  if (callerId) {
    const denied = await checkRateLimit(
      userClient, callerId, 'clip-public-track', 600, 3600, { failClosed: true },
    );
    if (denied) return denied;
  } else {
    const anonKey = await ipBucketKey(req);
    const denied = await checkRateLimit(
      adminClient, anonKey, 'clip-public-track:anon', 60, 3600, { failClosed: true },
    );
    if (denied) return denied;
  }

  // Look the row up via the column-redacted `public_runs` view rather
  // than the base `runs` table. The base-table SELECT policy
  // `public runs are readable by anyone` was dropped in 20260701_001,
  // so a non-owner querying `runs.id = ?` now returns zero rows and
  // every clip request would 404. The view's underlying definer-owned
  // query bypasses runs RLS, returns only `is_public = true` rows,
  // and exposes the two columns we need (user_id, is_public). The
  // `track_url` column was removed from the view in migration
  // 20260924_001 per audit/storage (2026-05-25); we derive the path
  // from `user_id + runId` below using the same shape the
  // 20260621_001 CHECK constraint enforces on writes. Owner reads
  // still return the row because the view is is-public-filtered
  // and the EF only ever runs on public runs (the share page
  // renders nothing for a private run).
  const { data: run, error: runErr } = await userClient
    .from('public_runs')
    .select('user_id, is_public')
    .eq('id', runId)
    .maybeSingle();
  if (runErr || !run) {
    return Response.json({ error: 'not found' }, { status: 404 });
  }

  // Derive the Storage path directly from the row owner + runId.
  // Matches the {user_id}/{run_id}.json.gz shape enforced by
  // CHECK on runs.track_url (migration 20260621_001).
  const trackPath = `${run.user_id}/${runId}.json.gz`;

  // Explicit visibility gate. RLS already filters this row lookup —
  // a non-owner asking for a private run lands in the !run branch
  // above. But the implicit RLS gate is fragile: if a future policy
  // change loosens runs SELECT (e.g. club-visibility) the EF would
  // silently start serving non-public rows to clients that
  // shouldn't get them. Make the contract loud instead — a
  // non-owner caller must be hitting an explicitly-public run.
  // audit/auth (2026-05-25) flagged the fragile null!==<uuid>
  // shape: it works today because callerId is `string | null`
  // and a null compared with any UUID falls to the non-owner
  // branch, but a future refactor that normalises callerId to
  // `''` or a sentinel would silently treat an anon caller as
  // the owner of a private run. The explicit null check makes
  // the contract loud.
  const isOwnerBypass = callerId !== null && callerId === run.user_id;
  if (!run.is_public && !isOwnerBypass) {
    return Response.json({ error: 'not found' }, { status: 404 });
  }

  const { data: blob, error: dlErr } = await adminClient.storage
    .from('runs')
    .download(trackPath);
  if (dlErr || !blob) {
    return Response.json({ error: 'track download failed' }, { status: 502 });
  }

  const gz = new Uint8Array(await blob.arrayBuffer());
  // Cap the gzipped blob at 5 MB before we even start decompressing.
  // The runs Storage bucket allows up to 25 MB per object; in practice
  // a real run track is well under 1 MB compressed. Anything bigger is
  // either pathological data or an attempt to chain gzip + JSON.parse
  // into a memory amplifier on the EF instance.
  if (gz.byteLength > 5 * 1024 * 1024) {
    return Response.json({ error: 'track too large' }, { status: 502 });
  }
  const ds = new (globalThis as { DecompressionStream: typeof DecompressionStream })
    .DecompressionStream('gzip');
  const stream = new Response(gz).body!.pipeThrough(ds);
  const txt = await new Response(stream).text();
  const points = JSON.parse(txt);
  if (!Array.isArray(points)) {
    return Response.json({ error: 'malformed track' }, { status: 502 });
  }
  // Bound the decompressed point count too — gzip ratios on JSON
  // floats can hit 20× and we don't want a 1 MB blob to expand into
  // a 50k+ point walk through clip_track_for_user. Real tracks top
  // out around 10k points (a 20 km run logged at 1 Hz).
  if (points.length > 50_000) {
    return Response.json({ error: 'track too long' }, { status: 502 });
  }

  if (callerId === run.user_id) {
    return Response.json({ points });
  }

  // Go through the service-role admin client for the clip RPC.
  // Migration 20260603_001 (f05dcb4) revoked EXECUTE on
  // clip_track_for_user from anon to close the residual-zone probe
  // documented in decisions §33; the EF is the only legitimate
  // anon-callable entry point, so it must use the service-role grant
  // (kept available to service_role + authenticated) to call the
  // RPC. Doing this here also lets us drop the anon-vs-authenticated
  // userClient branch from the call site — the cookie-based JWT was
  // never used for this read, only the row lookup above.
  const { data: clipped, error: clipErr } = await adminClient.rpc(
    'clip_track_for_user',
    { target_user_id: run.user_id, points },
  );
  if (clipErr) {
    return Response.json({ error: 'clip failed' }, { status: 500 });
  }
  return Response.json({ points: clipped ?? [] });
}));
