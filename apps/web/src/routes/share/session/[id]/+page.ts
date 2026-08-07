import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { env } from '$env/dynamic/public';
import { lookupSharedSession } from '$lib/share/share_session_lookup';
import { DEFAULT_SITE_URL } from '$lib/core/site_url';

// Per-request SSR via the production entity-SSR Lambda — CloudFront routes
// /share/session/* to the Lambda Function URL, which bakes the per-plan
// <title> + Open Graph + canonical + JSON-LD into the response HTML before a
// crawler or chat-app unfurler (neither runs the SPA's JS) can see it.
//
// `prerender = false` opts out of the module-level `prerender: { default:
// true }` so adapter-static doesn't bake per-id HTML at build time — a session
// plan can flip public/private after the build. This PageLoad still runs under
// the SvelteKit dev server so /share/session/[id] works locally without the
// Lambda; the public plan is fetched directly (RLS gates the read on
// is_public, so anon / logged-out viewers see only public plans).
export const prerender = false;


export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedSession(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const siteUrl = env.PUBLIC_SITE_URL || DEFAULT_SITE_URL;
	return {
		id: params.id,
		session: lookup.session,
		displayName: lookup.displayName,
		siteUrl,
	};
};
