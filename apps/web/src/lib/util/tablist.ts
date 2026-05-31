// WAI-ARIA tabs keyboard support (audit-findings 2026-05-30 High,
// WCAG 2.1.1): our hand-rolled `role="tablist"` strips already mark up
// role/aria-selected but had no Left/Right/Home/End navigation. This is
// the shared, page-agnostic handler: it roves focus among the
// `[role="tab"]` children of the tablist and activates the focused tab
// by triggering its existing click handler (which calls each page's
// setTab). No per-page focus refs needed.

// Pure index math — given the pressed key, the currently-focused tab
// index, and the tab count, return the index to move to (or the same
// index when the key isn't a navigation key). Exported for unit tests.
export function nextTabIndex(key: string, currentIndex: number, count: number): number {
	if (count <= 0) return currentIndex;
	switch (key) {
		case 'ArrowRight':
		case 'ArrowDown':
			return (currentIndex + 1) % count;
		case 'ArrowLeft':
		case 'ArrowUp':
			return (currentIndex - 1 + count) % count;
		case 'Home':
			return 0;
		case 'End':
			return count - 1;
		default:
			return currentIndex;
	}
}

// Attach to the tablist element's `onkeydown`. Moves focus + activates
// the target tab. Safe to call with any keyboard event — it no-ops on
// non-navigation keys.
const NAV_KEYS = new Set([
	'ArrowRight',
	'ArrowLeft',
	'ArrowUp',
	'ArrowDown',
	'Home',
	'End',
]);

export function handleTablistKeydown(e: KeyboardEvent): void {
	// Only act on the roving-navigation keys. Anything else (Tab, Enter,
	// Space, typing) must pass through untouched — without this guard a
	// keypress while the tablist container itself holds focus (it carries
	// tabindex=-1) would fall through and wrongly activate the first tab,
	// e.g. eating Tab and trapping focus.
	if (!NAV_KEYS.has(e.key)) return;
	const list = e.currentTarget as HTMLElement | null;
	if (!list) return;
	const tabs = Array.from(list.querySelectorAll<HTMLElement>('[role="tab"]'));
	if (tabs.length === 0) return;
	const currentIndex = tabs.findIndex((t) => t === document.activeElement);
	// If focus isn't on a tab yet (e.g. the container), start from 0.
	const from = currentIndex === -1 ? 0 : currentIndex;
	const next = nextTabIndex(e.key, from, tabs.length);
	e.preventDefault();
	if (next === currentIndex) return;
	tabs[next].focus();
	tabs[next].click();
}
