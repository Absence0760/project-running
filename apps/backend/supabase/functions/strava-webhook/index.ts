import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req: Request) => {
  // GET: Strava webhook verification
  if (req.method === 'GET') {
    const url = new URL(req.url);
    const challenge = url.searchParams.get('hub.challenge');
    const verifyToken = url.searchParams.get('hub.verify_token');

    if (verifyToken !== Deno.env.get('STRAVA_VERIFY_TOKEN')) {
      return new Response('Forbidden', { status: 403 });
    }

    return Response.json({ 'hub.challenge': challenge });
  }

  // POST: Activity event from Strava
  const { object_type, object_id, aspect_type, owner_id } = await req.json();

  if (object_type !== 'activity' || aspect_type !== 'create') {
    return new Response('OK');
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Look up user by Strava athlete ID
  const { data: integration } = await supabase
    .from('integrations')
    .select('user_id, access_token')
    .eq('provider', 'strava')
    .eq('external_id', String(owner_id))
    .single();

  if (!integration) {
    return new Response('User not found', { status: 404 });
  }

  // TODO: Fetch activity detail + GPS stream from Strava API
  // TODO: Map to Run and upsert into runs table

  return new Response('OK');
});
