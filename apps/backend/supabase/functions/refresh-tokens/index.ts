import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async () => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Find Strava integrations with tokens expiring within 1 hour
  const { data: expiring } = await supabase
    .from('integrations')
    .select('id, user_id, refresh_token')
    .eq('provider', 'strava')
    .lt('token_expiry', new Date(Date.now() + 3600_000).toISOString());

  let refreshed = 0;

  for (const integration of expiring ?? []) {
    const response = await fetch('https://www.strava.com/oauth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        client_id: Deno.env.get('STRAVA_CLIENT_ID'),
        client_secret: Deno.env.get('STRAVA_CLIENT_SECRET'),
        refresh_token: integration.refresh_token,
        grant_type: 'refresh_token',
      }),
    });

    if (!response.ok) continue;

    const tokens = await response.json();

    await supabase
      .from('integrations')
      .update({
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        token_expiry: new Date(tokens.expires_at * 1000).toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', integration.id);

    refreshed++;
  }

  return Response.json({ refreshed });
});
