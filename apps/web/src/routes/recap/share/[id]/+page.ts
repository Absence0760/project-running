import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { lookupSharedRecap, recapPeriodLabel } from '$lib/share/share_recap_lookup';

// Per-request SSR via apps/web/lambda/share-recap in production — CloudFront
// routes /recap/share/* to the Lambda Function URL, which fetches the frozen
// snapshot + display name and bakes the per-recap <title> + Open Graph +
// Twitter tags into the response HTML before crawlers see it. This PageLoad
// still runs under the SvelteKit dev server so the path works locally without
// the Lambda. Mirrors /share/run/[id].
//
// `prerender = false` opts out of the module-level default so adapter-static
// doesn't try to bake per-id HTML at build time; the Lambda owns this path in
// prod.
export const prerender = false;

export const load: PageLoad = async ({ params }) => {
	const { recap } = await lookupSharedRecap(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const periodLabel = recap ? recapPeriodLabel(recap.periodKind, recap.periodKey) : null;
	return { id: params.id, recap, periodLabel };
};
