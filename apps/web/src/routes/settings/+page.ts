import { redirect } from '@sveltejs/kit';

// `/settings` itself has no content — it's just the index of the
// settings tabs. Bounce visitors to the first tab so the sidebar
// "Settings" link always lands somewhere useful.
export const prerender = true;

export function load() {
	throw redirect(307, '/settings/account');
}
