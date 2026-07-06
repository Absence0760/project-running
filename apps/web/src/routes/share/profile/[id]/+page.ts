import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { env } from '$env/dynamic/public';
import { lookupSharedProfile } from '$lib/share/share_profile_lookup';

// Per-request SSR via the production entity-SSR Lambda — CloudFront
// routes /share/profile/* to the Lambda Function URL, which fetches the
// public profile + bakes the per-runner <title> + Open Graph + canonical
// + ProfilePage JSON-LD into the response HTML before crawlers can see
// it. This PageLoad still runs under the SvelteKit dev server so the page
// works locally without the Lambda.
export const prerender = false;

const DEFAULT_SITE_URL = 'https://threkir.com';

export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedProfile(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const siteUrl = env.PUBLIC_SITE_URL || DEFAULT_SITE_URL;
	return { id: params.id, profile: lookup.profile, siteUrl };
};
