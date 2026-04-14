import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req: Request) => {
  const { code, scope } = await req.json();
  const authHeader = req.headers.get('Authorization')!;

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return new Response('Unauthorized', { status: 401 });

  // Step 1: Exchange auth code for tokens
  const tokenResponse = await fetch('https://www.strava.com/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: Deno.env.get('STRAVA_CLIENT_ID'),
      client_secret: Deno.env.get('STRAVA_CLIENT_SECRET'),
      code,
      grant_type: 'authorization_code',
    }),
  });

  const tokens = await tokenResponse.json();

  // Step 2: Store tokens
  await supabase.from('integrations').upsert({
    user_id: user.id,
    provider: 'strava',
    access_token: tokens.access_token,
    refresh_token: tokens.refresh_token,
    token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
    external_id: String(tokens.athlete.id),
    scope,
  }, { onConflict: 'user_id,provider' });

  // Step 3: Backfill last 90 days
  // TODO: Paginate through GET /athlete/activities
  // TODO: For each activity, fetch GPS stream and upsert as Run

  return Response.json({ imported: 0, athlete_id: String(tokens.athlete.id) });
});
