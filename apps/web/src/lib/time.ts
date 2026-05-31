// Pure time/date formatting helpers shared across web surfaces.
// No runes here (plain `.ts`) so the helpers are unit-testable via `tsx --test`.

/**
 * Relative-time label for a feed/comment/notification timestamp:
 * `just now`, `Nm ago`, `Nh ago`, `Nd ago` (under 30 days), otherwise a
 * localized `Mon D, YYYY` date.
 *
 * `now` is injectable so the relative branches are deterministic in tests;
 * callers pass only the ISO string and get `Date.now()` by default.
 */
export function formatRelativeTime(iso: string, now: number = Date.now()): string {
	const ms = now - new Date(iso).getTime();
	const mins = Math.floor(ms / 60_000);
	if (mins < 1) return 'just now';
	if (mins < 60) return `${mins}m ago`;
	const hrs = Math.floor(mins / 60);
	if (hrs < 24) return `${hrs}h ago`;
	const days = Math.floor(hrs / 24);
	if (days < 30) return `${days}d ago`;
	return new Date(iso).toLocaleDateString(undefined, {
		month: 'short',
		day: 'numeric',
		year: 'numeric',
	});
}
