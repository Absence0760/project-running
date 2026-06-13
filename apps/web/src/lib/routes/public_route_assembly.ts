/**
 * Pure, rune-free helper shared by the two non-owner / anon route-read
 * paths in core/data.ts (`fetchPublicRoute` and `fetchRouteById`'s
 * non-owner branch). Both read the redacted `public_routes` metadata row
 * AND the server-clipped waypoints, and both reads key only on the route
 * id — so they are independent and must run concurrently rather than
 * serialise (the share / OG-image path was paying two sequential round
 * trips). This helper fires both at once via `Promise.all` and returns
 * null when the metadata row is absent or not public, preserving the
 * original semantics.
 *
 * Kept here (no Supabase import, no `$state`) so it is `tsx --test`-able
 * — see public_route_assembly.test.ts.
 */
export async function assemblePublicRoute<Meta, Clip>(
	readMeta: () => Promise<Meta | null>,
	readClip: () => Promise<Clip>,
): Promise<{ meta: Meta; clipped: Clip } | null> {
	const [meta, clipped] = await Promise.all([readMeta(), readClip()]);
	if (meta == null) return null;
	return { meta, clipped };
}
