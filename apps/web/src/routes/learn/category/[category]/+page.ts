import type { EntryGenerator, PageLoad } from './$types';
import { error } from '@sveltejs/kit';
import { env } from '$env/dynamic/public';
import { guidesByCategory } from '$lib/learn/guides';
import { CATEGORIES, getCategory } from '$lib/learn/categories';
import { siteOrigin } from '$lib/core/site_url';

export const prerender = true;


export const entries: EntryGenerator = () => CATEGORIES.map((c) => ({ category: c.id }));

export const load: PageLoad = ({ params }) => {
	const category = getCategory(params.category);
	if (!category) throw error(404, 'Category not found');
	const siteUrl = siteOrigin(env.PUBLIC_SITE_URL);
	return {
		siteUrl,
		category,
		guides: guidesByCategory(category.id),
	};
};
