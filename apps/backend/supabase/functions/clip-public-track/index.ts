import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { withSentry } from '../_shared/sentry.ts';

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

  let body: { run_id?: unknown };
  try {
    body = await req.json();
  } catch (_) {
    return Response.json({ error: 'invalid json body' }, { status: 400 });
  }
  const runId = body.run_id;
  if (typeof runId !== 'string' || runId.length === 0) {
    return Response.json({ error: 'run_id required' }, { status: 400 });
  }

  const { data: run, error: runErr } = await userClient
    .from('runs')
    .select('user_id, track_url, is_public')
    .eq('id', runId)
    .maybeSingle();
  if (runErr || !run || !run.track_url) {
    return Response.json({ error: 'not found' }, { status: 404 });
  }

  // Defence-in-depth against track_url forgery (audit/storage High).
  // A CHECK constraint on runs.track_url (migration 20260621_001)
  // pins the column to {user_id}/{run_id}.json.gz at write time.
  // This assertion catches anything that slipped through (legacy
  // rows pre-validate, or a future weakening of the CHECK) — without
  // it, an attacker rewriting their own row to a victim's path
  // could trick the service-role downloader into reading any blob.
  const expected = `${run.user_id}/${runId}.json.gz`;
  if (run.track_url !== expected) {
    return Response.json({ error: 'track_url mismatch' }, { status: 422 });
  }

  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const { data: blob, error: dlErr } = await adminClient.storage
    .from('runs')
    .download(run.track_url);
  if (dlErr || !blob) {
    return Response.json({ error: 'track download failed' }, { status: 502 });
  }

  const gz = new Uint8Array(await blob.arrayBuffer());
  const ds = new (globalThis as { DecompressionStream: typeof DecompressionStream })
    .DecompressionStream('gzip');
  const stream = new Response(gz).body!.pipeThrough(ds);
  const txt = await new Response(stream).text();
  const points = JSON.parse(txt);
  if (!Array.isArray(points)) {
    return Response.json({ error: 'malformed track' }, { status: 502 });
  }

  if (callerId === run.user_id) {
    return Response.json({ points });
  }

  const { data: clipped, error: clipErr } = await userClient.rpc(
    'clip_track_for_user',
    { target_user_id: run.user_id, points },
  );
  if (clipErr) {
    return Response.json({ error: 'clip failed' }, { status: 500 });
  }
  return Response.json({ points: clipped ?? [] });
}));
