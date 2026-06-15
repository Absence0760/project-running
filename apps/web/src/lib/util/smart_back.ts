import { afterNavigate } from '$app/navigation';

/**
 * Wire a history-aware back control. When the user soft-navigated into the
 * current page from another in-app page, `handle` pops history so they return
 * to wherever they actually came from (a club's templates tab, a workout
 * detail, …) rather than the link's static parent. On a hard load / deep link
 * there is no in-app history entry to pop, so `handle` is a no-op and the
 * anchor's `href` takes over — which is also what restores a fresh list.
 *
 * `history.back()` (a popstate) re-triggers SvelteKit's snapshot restore on the
 * source page, so a list's scroll/filter state survives the return trip; a
 * plain `href` soft-nav would not. That makes "pop to the referrer" strictly
 * better than a hardcoded parent for every detail/create page reachable from
 * more than one surface.
 *
 * Pass `match` to restrict which referrers enable the pop (e.g. a page that
 * wants its static href for arrivals from unrelated surfaces); omit it to pop
 * for ANY in-app referrer.
 *
 * Call once at the top of a component `<script>` (it registers `afterNavigate`,
 * which must run during component init), then bind `handle` to the back link's
 * `onclick` while keeping its `href` as the fallback parent.
 */
export function smartBack(match?: (fromPath: string) => boolean): {
	readonly canPop: boolean;
	handle: (e: MouseEvent) => void;
} {
	let canPop = false;
	afterNavigate(({ from }) => {
		if (canPop) return;
		const fromPath = from?.url.pathname;
		if (!fromPath) return;
		if (match && !match(fromPath)) return;
		canPop = true;
	});
	return {
		get canPop() {
			return canPop;
		},
		handle(e: MouseEvent) {
			if (!canPop) return;
			e.preventDefault();
			history.back();
		}
	};
}
