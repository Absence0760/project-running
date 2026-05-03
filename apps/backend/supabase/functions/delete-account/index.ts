import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import {
  createClient,
  type SupabaseClient,
} from 'https://esm.sh/@supabase/supabase-js@2';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { enforceBodyLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';

const PAGE = 1000;

// Recursively delete every blob under `prefix` in `bucket`. Supabase
// Storage's `list` returns subdirectory pseudo-entries (id = null)
// alongside files; bulk-removing those entries is a no-op against
// flat object keys, so we filter them out and recurse explicitly.
// Without this, `${user.id}/exports/<ts>.{csv,zip}` blobs survive
// account deletion even though the parent prefix is "drained" — a
// privacy-deletion failure mode that audit/storage pass 3 caught.
//
// Throws on any list / remove error so the caller can abort before
// dropping the auth user. A partial Storage drain followed by the
// auth-row cascade orphans blobs with no row to point at them — a
// privacy-deletion silent failure that the user can't observe and
// can't retry (their auth row is already gone).
async function deletePrefix(
  client: SupabaseClient,
  bucket: string,
  prefix: string,
): Promise<void> {
  while (true) {
    const { data: entries, error: listErr } = await client.storage
      .from(bucket)
      .list(prefix, { limit: PAGE });
    if (listErr) {
      throw new Error(`list ${bucket}/${prefix} failed: ${listErr.message}`);
    }
    if (!entries || entries.length === 0) break;

    const files = entries.filter((e) => e.id !== null);
    const folders = entries.filter((e) => e.id === null);

    if (files.length > 0) {
      const { error: rmErr } = await client.storage
        .from(bucket)
        .remove(files.map((f) => `${prefix}/${f.name}`));
      if (rmErr) {
        throw new Error(`remove in ${bucket}/${prefix} failed: ${rmErr.message}`);
      }
    }
    for (const folder of folders) {
      await deletePrefix(client, bucket, `${prefix}/${folder.name}`);
    }

    // Less than a full page means no more entries exist at this
    // prefix. Folders we recursed into are now drained (so subsequent
    // lists won't return them); removed files are gone. Skip the
    // extra round-trip that would just confirm an empty page.
    if (entries.length < PAGE) break;
  }
}

serve(withSentry('delete-account', async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // delete-account takes no body — clamp tightly.
  const tooBig = enforceBodyLimit(req, 256);
  if (tooBig) return tooBig;

  const authHeader = req.headers.get('Authorization')!;
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return new Response('Unauthorized', { status: 401 });

  // 3/hour. Destructive endpoint, but we want a typo or double-tap
  // to fail fast rather than panic-spam-cancelling. Once a delete
  // succeeds the user's auth row is gone, so subsequent calls 401.
  // Fail-closed: if the rate-limit RPC errors we 503 rather than
  // letting unbounded delete attempts through (the throttle is the
  // only thing between a stolen JWT and account-destruction spam).
  const denied = await checkRateLimit(userClient, user.id, 'delete-account', 3, 3600, {
    failClosed: true,
  });
  if (denied) return denied;

  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Delete Storage files. The `runs` bucket holds gzipped tracks +
  // per-user export blobs at `{user.id}/exports/<ts>.{csv,zip}`; the
  // `run-photos` bucket holds run photos (public-read, so leaving
  // them behind means saved URLs keep resolving even after account
  // deletion). deletePrefix recurses through pseudo-folders so the
  // exports/ subdirectory is fully drained alongside the top-level
  // tracks. A partial drain followed by the auth-row cascade orphans
  // blobs with no row to point at them, so we abort before deleting
  // the auth user — the user can retry once Storage recovers.
  try {
    for (const bucket of ['runs', 'run-photos']) {
      await deletePrefix(adminClient, bucket, user.id);
    }
  } catch (err) {
    console.error('delete-account: Storage drain failed:', err);
    return Response.json(
      { error: 'storage drain failed' },
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  // Row data cascades from auth.users via ON DELETE CASCADE on most
  // tables (runs, routes, user_profiles, user_settings, etc.). Deleting
  // the auth user triggers those cascades automatically.

  const { error } = await adminClient.auth.admin.deleteUser(user.id);
  if (error) {
    // Log the underlying message via Sentry / function logs but don't
    // bounce it back to the client — Supabase / GoTrue error text can
    // expose internal identifiers and schema names that are useless
    // to legitimate callers.
    console.error('delete-account: admin.deleteUser failed:', error);
    return Response.json(
      { error: 'delete failed' },
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  return Response.json({ ok: true });
}));
