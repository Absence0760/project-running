import type { PageLoad } from './$types';

// Public, account-optional charity fundraiser page (fundraising.md). A plain
// client-rendered SPA page like /share/event/[id]/results: the data is
// account-optional (an anon stranger can view + donate) but gated by the
// fundraisers-visible RLS + the fundraiser_feed / fundraiser_totals RPCs, which
// project only public-safe columns. prerender=false opts out of the module-
// level prerender so adapter-static doesn't bake per-id HTML; ssr=false keeps
// it a pure browser render. `donated` drives the post-checkout success poll.
export const prerender = false;
export const ssr = false;

export const load: PageLoad = ({ params, url }) => {
	return { id: params.id, donated: url.searchParams.get('donated') };
};
