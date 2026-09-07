import { createServerClient } from '@supabase/ssr';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';
import type { Cookies } from '@sveltejs/kit';
import type { AppDatabase } from './database';

export function createClient(cookies: Cookies) {
	return createServerClient<AppDatabase>(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
		cookies: {
			getAll: () => cookies.getAll(),
			setAll: (cookiesToSet: { name: string; value: string; options: Record<string, unknown> }[]) => {
				cookiesToSet.forEach(({ name, value, options }: { name: string; value: string; options: Record<string, unknown> }) => {
					cookies.set(name, value, { ...options, path: '/' });
				});
			},
		},
	});
}
