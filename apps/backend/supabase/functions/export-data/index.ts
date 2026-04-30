import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';

serve(async (req: Request) => {
  // Authenticate before parsing the body. Otherwise a malformed-JSON
  // request from an unauthenticated caller produces a 500 (or unhandled
  // Deno exception) distinguishable from a 401, and any future code
  // added between the parse and the auth check would run unauth'd.
  const authHeader = req.headers.get('Authorization')!;

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response('Unauthorized', { status: 401 });

  // Free 2/h, pro 8/h. Heavy operation (zip-and-ship of every run +
  // track) so even Pro doesn't get unlimited; the higher Pro ceiling
  // accommodates "I'm migrating off the platform / making backups
  // for several reasons today" without the 1/2-hour wait.
  const denied = await checkRateLimitTiered(supabase, user.id, 'export-data', 2, 8, 3600);
  if (denied) return denied;

  // The function is a stub (TODO: fetch runs, convert to GPX/CSV,
  // upload to Storage, return signed URL). Until the implementation
  // lands, return 501 — previously this returned a fake
  // `placeholder.supabase.co` URL that would 404 on use, surfacing as
  // a confusing client-side failure when promoted.
  return new Response('Not implemented', { status: 501 });
});
