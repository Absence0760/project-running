import type { PageLoad } from './$types';
import { env } from '$env/dynamic/public';
import { listGuides, nonEmptyCategories } from '$lib/learn/guides';

// The Learn hub is finite, evergreen, and known at build time, so it
// prerenders to a single static HTML file served by CloudFront from S3
// with zero runtime cost — unlike /share/*, whose per-id content is
// mutable and Lambda-rendered. See docs/features/learn.md.
export const prerender = true;

const DEFAULT_SITE_URL = 'https://threkir.com';

export const load: PageLoad = () => {
	const siteUrl = env.PUBLIC_SITE_URL || DEFAULT_SITE_URL;
	return {
		siteUrl,
		guides: listGuides(),
		categories: nonEmptyCategories(),
	};
};
