import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { checkRateLimit } from '../_shared/rate_limit.ts';
import { withSentry } from '../_shared/sentry.ts';

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
  // per-user export blobs; the `run-photos` bucket holds run photos
  // (public-read, so leaving them behind means saved URLs keep
  // resolving even after account deletion). Both keyed under
  // `{user.id}/`.
  for (const bucket of ['runs', 'run-photos']) {
    const { data: files } = await adminClient.storage
      .from(bucket)
      .list(user.id, { limit: 1000 });
    if (files && files.length > 0) {
      const paths = files.map((f) => `${user.id}/${f.name}`);
      await adminClient.storage.from(bucket).remove(paths);
    }
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
