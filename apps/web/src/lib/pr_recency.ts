/// Plain-English relative age of a personal-record date, e.g. "today",
/// "3 weeks ago", "2 years ago". Used to soften the PR card for returning
/// runners — an all-time best from years back reads as context, not a
/// taunt (comeback persona #28). Mirrors the Dart `relativeAge` in
/// apps/mobile_android/lib/pr_recency.dart — keep in lockstep.
export function relativeAge(iso: string, nowMs: number = Date.now()): string {
	const then = Date.parse(iso);
	if (Number.isNaN(then)) return '';
	const days = Math.floor((nowMs - then) / 86_400_000);
	if (days <= 0) return 'today';
	if (days === 1) return 'yesterday';
	if (days < 7) return `${days} days ago`;
	if (days < 31) {
		const w = Math.floor(days / 7);
		return w === 1 ? 'a week ago' : `${w} weeks ago`;
	}
	if (days < 365) {
		const m = Math.floor(days / 30);
		return m === 1 ? 'a month ago' : `${m} months ago`;
	}
	const y = Math.floor(days / 365);
	return y === 1 ? 'a year ago' : `${y} years ago`;
}
