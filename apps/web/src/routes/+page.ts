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

// `/` is the site's only indexable non-Learn surface, and everything
// `docs/features/seo.md` promises for it -- title, canonical, description,
// og/twitter, Organization + WebSite JSON-LD -- is built by components, which
// a client-rendered route contributes to no artifact. Prerendering is what
// writes them into `build/index.html`, the file CloudFront serves as the site
// root. It is load-bearing with `svelte.config.js`'s `fallback: "200.html"`:
// adapter-static writes the fallback AFTER the prerendered pages and to the
// name it is given, so a fallback still called `index.html` silently replaces
// this page with the component-less shell. decisions § 1268.
export const prerender = true;
