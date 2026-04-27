import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

  const { format } = await req.json();

  // TODO: Fetch all user runs
  // TODO: Convert to GPX or CSV based on format
  // TODO: Upload to Supabase Storage
  // TODO: Return signed URL

  return Response.json({
    url: `https://placeholder.supabase.co/storage/v1/exports/${user.id}/export.${format}`,
    expires_in: 600,
  });
});
