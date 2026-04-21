import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req: Request) => {
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

  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Delete Storage files (tracks in the `runs` bucket under user_id/).
  const { data: files } = await adminClient.storage
    .from('runs')
    .list(user.id, { limit: 1000 });
  if (files && files.length > 0) {
    const paths = files.map((f) => `${user.id}/${f.name}`);
    await adminClient.storage.from('runs').remove(paths);
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
});
