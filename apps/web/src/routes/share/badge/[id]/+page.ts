import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { lookupSharedBadge } from '$lib/share/share_badge_lookup';

// Per-request SSR via apps/web/lambda/share-badge in production. This PageLoad
// runs under the SvelteKit dev server so /share/badge/[id] works locally
// without the Lambda. prerender = false opts out of the static prerender so
// adapter-static doesn't bake per-id HTML at build time.
export const prerender = false;

export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedBadge(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return { id: params.id, badge: lookup.badge, displayName: lookup.displayName };
};
