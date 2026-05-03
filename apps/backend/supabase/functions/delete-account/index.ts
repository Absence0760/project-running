import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import {
  createClient,
  type SupabaseClient,
} from 'https://esm.sh/@supabase/supabase-js@2';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';

const PAGE = 1000;

// Recursively delete every blob under `prefix` in `bucket`. Supabase
// Storage's `list` returns subdirectory pseudo-entries (id = null)
// alongside files; bulk-removing those entries is a no-op against
// flat object keys, so we filter them out and recurse explicitly.
// Without this, `${user.id}/exports/<ts>.{csv,zip}` blobs survive
// account deletion even though the parent prefix is "drained" — a
// privacy-deletion failure mode that audit/storage pass 3 caught.
async function deletePrefix(
  client: SupabaseClient,
  bucket: string,
  prefix: string,
): Promise<void> {
  while (true) {
    const { data: entries } = await client.storage
      .from(bucket)
      .list(prefix, { limit: PAGE });
    if (!entries || entries.length === 0) break;

    const files = entries.filter((e) => e.id !== null);
    const folders = entries.filter((e) => e.id === null);

    if (files.length > 0) {
      await client.storage
        .from(bucket)
        .remove(files.map((f) => `${prefix}/${f.name}`));
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
  const denied = await checkRateLimit(userClient, user.id, 'delete-account', 3, 3600);
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
  // tracks.
  for (const bucket of ['runs', 'run-photos']) {
    await deletePrefix(adminClient, bucket, user.id);
  }

  // Row data cascades from auth.users via ON DELETE CASCADE on most
  // tables (runs, routes, user_profiles, user_settings, etc.). Deleting
  // the auth user triggers those cascades automatically.

  const { error } = await adminClient.auth.admin.deleteUser(user.id);
  if (error) {
    return Response.json(
      { error: error.message },
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  return Response.json({ ok: true });
}));
