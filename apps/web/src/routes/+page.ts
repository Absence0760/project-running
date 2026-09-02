import type { PageLoad } from './$types';
import { env } from '$env/dynamic/public';
import { siteOrigin } from '$lib/core/site_url';

// Canonical host for the landing page's <link rel="canonical"> + og:url
// + JSON-LD URLs. Same source + fallback as /sitemap.xml, /learn, and
// the share pages so the host stays consistent across the indexable
// surface (preview vs prod set PUBLIC_SITE_URL; local falls through to
// the prod host).

export const load: PageLoad = () => {
	return { siteUrl: siteOrigin(env.PUBLIC_SITE_URL) };
};
