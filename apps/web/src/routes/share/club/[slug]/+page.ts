import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { env } from '$env/dynamic/public';
import { lookupSharedClub } from '$lib/share/share_club_lookup';

// Per-request SSR via the production entity-SSR Lambda — CloudFront
// routes /share/club/* to the Lambda Function URL, which fetches the
// public club + bakes the per-club <title> + Open Graph + canonical +
// SportsOrganization JSON-LD into the response HTML before crawlers can
// see it. This PageLoad still runs under the SvelteKit dev server so the
// page works locally without the Lambda.
export const prerender = false;

const DEFAULT_SITE_URL = 'https://threkir.com';

export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedClub(
		params.slug,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	const siteUrl = env.PUBLIC_SITE_URL || DEFAULT_SITE_URL;
	return { slug: params.slug, club: lookup.club, siteUrl };
};
