import type { PageLoad } from './$types';

// Public, account-optional results page. Unlike /share/run + /share/route
// (per-request SSR via a Lambda for OG unfurling), this is a plain client-
// rendered SPA page: the data is account-optional but not crawl-meta-sensitive,
// and the event-visibility RLS gates every read. prerender=false opts out of
// the module-level `prerender: { default: true }` so adapter-static doesn't try
// to bake per-id HTML at build time; ssr=false keeps it a pure browser render.
export const prerender = false;
export const ssr = false;

export const load: PageLoad = ({ params, url }) => {
	return { id: params.id, instance: url.searchParams.get('instance') ?? '' };
};
