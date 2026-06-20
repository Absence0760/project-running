import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.106.1';
import { checkRateLimitTiered } from '../_shared/rate_limit.ts';
import { readJsonWithLimit } from '../_shared/body_limit.ts';
import { withSentry } from '../_shared/sentry.ts';

// Pull upcoming RunSignUp races near a region into race_listings. The seam
// exists so v1 (user-submitted + on-demand import) can grow into auto-sync
// without a new function. Like race-results-import it is GATED on the missing
// RunSignUp API key: until the key is provisioned this returns 503 and writes
// nothing — the fail-closed default required by the missing-credential rule.
//
// The actual upcoming-races fetch + upsert (api_key/api_secret query, the
// /Rest/races endpoint, ON CONFLICT (provider, provider_race_id)) is a scoped
// follow-up; building it ahead of the credential would only add an untestable
// network path. The contract — auth, rate limit, fail-closed gate — is here.

interface RequestBody {
  near?: unknown; // { lng, lat, radius_m } region hint (future)
}

Deno.serve(withSentry('race-listings-sync', async (req: Request) => {
  const guarded = await readJsonWithLimit<RequestBody>(req, 1024);
  if ('tooLarge' in guarded) return guarded.tooLarge;

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const denied = await checkRateLimitTiered(supabase, user.id, 'race-listings-sync', 2, 8, 3600);
  if (denied) return denied;

  // Fail closed on the missing provider key — the whole RunSignUp leg is
  // inert until the credential lands (integrations.md + decisions ADR).
  const apiKey = Deno.env.get('RUNSIGNUP_API_KEY');
  const apiSecret = Deno.env.get('RUNSIGNUP_API_SECRET');
  if (!apiKey || !apiSecret) {
    return Response.json({ error: 'provider_not_configured' }, { status: 503 });
  }

  // Provisioned-key path: the upcoming-races fetch + upsert is a scoped
  // follow-up (see the header note). Return a no-op success so a provisioned
  // deploy doesn't error while that path is built.
  return Response.json({ synced: 0 });
}));
