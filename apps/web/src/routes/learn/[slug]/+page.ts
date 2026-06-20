import type { EntryGenerator, PageLoad } from './$types';
import { error } from '@sveltejs/kit';
import { env } from '$env/dynamic/public';
import { getGuide, listGuideSlugs } from '$lib/learn/guides';

// Finite, evergreen, known at build time → every guide prerenders to a
// static HTML file in build/learn/<slug>/. entries() enumerates the
// dynamic [slug] segment so adapter-static bakes them all.
export const prerender = true;

const DEFAULT_SITE_URL = 'https://threkir.com';

export const entries: EntryGenerator = () => listGuideSlugs().map((slug) => ({ slug }));

export const load: PageLoad = ({ params }) => {
	const guide = getGuide(params.slug);
	if (!guide) throw error(404, 'Guide not found');
	const siteUrl = env.PUBLIC_SITE_URL || DEFAULT_SITE_URL;
	return {
		siteUrl,
		guide,
		categoryId: guide.category,
	};
};
