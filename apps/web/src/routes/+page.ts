import type { PageLoad } from './$types';
import { env } from '$env/dynamic/public';

// Canonical host for the landing page's <link rel="canonical"> + og:url
// + JSON-LD URLs. Same source + fallback as /sitemap.xml, /learn, and
// the share pages so the host stays consistent across the indexable
// surface (preview vs prod set PUBLIC_SITE_URL; local falls through to
// the prod host).
const DEFAULT_SITE_URL = 'https://threkir.com';

export const load: PageLoad = () => {
	return { siteUrl: env.PUBLIC_SITE_URL || DEFAULT_SITE_URL };
};
