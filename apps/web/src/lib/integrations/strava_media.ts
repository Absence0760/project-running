/// Pure helpers for importing photos out of a Strava bulk-export ZIP
/// (strava persona #19). Split from strava-zip.ts (which pulls in JSZip +
/// ./data → supabase + $env) so it's unit-testable with `tsx --test`.

/// Split a Strava `Media` CSV cell into individual in-ZIP photo paths.
/// Strava separates multiple media with `|`; older exports used `,`. Paths
/// are relative (e.g. `media/<activity_id>/<uuid>.jpg`).
export function parseStravaMediaPaths(cell: string | undefined): string[] {
	if (!cell) return [];
	return cell
		.split('|')
		.flatMap((s) => s.split(','))
		.map((s) => s.trim())
		.filter((s) => s.length > 0 && /\.(jpe?g|png|webp|heic)$/i.test(s));
}

export const STRAVA_PHOTO_MIME: Record<string, string> = {
	jpg: 'image/jpeg',
	jpeg: 'image/jpeg',
	png: 'image/png',
	webp: 'image/webp',
	heic: 'image/heic',
};
