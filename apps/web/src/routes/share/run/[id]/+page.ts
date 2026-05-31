import type { PageLoad } from './$types';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import { lookupSharedRun } from '$lib/share/share_run_lookup';

// Per-request SSR via apps/web/lambda/share-run in production —
// CloudFront routes /share/run/* to the Lambda Function URL, which
// fetches the run + display name and bakes the per-run <title> +
// Open Graph + Twitter tags into the response HTML before crawlers
// can see it. This PageLoad still runs under the SvelteKit dev
// server so /share/run/[id] works locally without standing up the
// Lambda. Persona-hunt finding Casual #4.
//
// `prerender = false` opts out of the module-level
// `prerender: { default: true }` so adapter-static doesn't try to
// bake per-id HTML files at build time. The Lambda owns this path in
// prod.
export const prerender = false;

export const load: PageLoad = async ({ params }) => {
	const lookup = await lookupSharedRun(
		params.id,
		PUBLIC_SUPABASE_URL && PUBLIC_SUPABASE_ANON_KEY
			? { supabaseUrl: PUBLIC_SUPABASE_URL, supabaseAnonKey: PUBLIC_SUPABASE_ANON_KEY }
			: null,
	);
	return { id: params.id, run: lookup.run, displayName: lookup.displayName };
};
