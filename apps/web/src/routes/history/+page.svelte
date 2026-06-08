<script lang="ts">
	import { onMount } from 'svelte';
	import { formatPace, formatDistance, sourceLabel, sourceColor } from '$lib/core/mock-data';
	import { formatDate, formatDuration } from '$lib/format/time';
	import { fetchRuns, deleteRuns, fetchActivities, fetchGymSetHistory, type ActivityRow } from '$lib/core/data';
	import { loadSettings, effective } from '$lib/settings/settings';
	import { periodStart } from '$lib/training/goals';
	import { auth } from '$lib/stores/auth.svelte';
	import RunEditor from '$lib/components/RunEditor.svelte';
	import GymEditor from '$lib/components/GymEditor.svelte';
	import FoodLogEditor from '$lib/components/FoodLogEditor.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { goto } from '$app/navigation';
	import { showToast } from '$lib/stores/toast.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import RunTrackPreview from '$lib/components/RunTrackPreview.svelte';
	import DateRangePicker from '$lib/components/DateRangePicker.svelte';
	import type { Run, RunSource } from '$lib/types';
	import { formatElevation, formatWeight } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import type { Snapshot } from './$types';

	let runs = $state<Run[]>([]);
	let loading = $state(true);
	let sourceFilter = $state<RunSource | 'all'>('all');
	// Default to all activities, consistent with the source filter. A
	// run-only default hid a walk-/cycle-/hike-only user's entire history
	// behind a filter they never set — their first view of /history was the
	// "No runs match these filters" dead-end (persona-hunt R5, casual).
	let activityFilter = $state<string>('all');
	type SortKey = 'newest' | 'oldest' | 'longest' | 'fastest';
	let sortKey = $state<SortKey>('newest');
	type DateRange = 'today' | 'week' | 'month' | 'year' | 'all' | 'custom';
	// Default scope = today's runs only. "All time" is opt-in and
	// streams in pages of PAGE_SIZE so a heavy account doesn't
	// pull thousands of rows on first paint.
	let dateRange = $state<DateRange>('today');

	/// First day of the week for the "Week" filter, mirroring the
	/// dashboard's `week_start_day` pref so the run list and the
	/// dashboard agree on where the week begins. Default `monday`.
	let weekStartDay = $state<'monday' | 'sunday'>('monday');

	const PAGE_SIZE = 50;
	let loadingMore = $state(false);
	let hasMore = $state(false);
	/// Tracks the last fetch mode so we only refetch on `paginated` ↔
	/// `full` transitions, not on every filter twiddle.
	let lastFetchMode = $state<'paginated' | 'full' | ''>('');
	/// ISO yyyy-mm-dd bounds for the custom-range picker. Empty string
	/// means unbounded on that side.
	let customFrom = $state('');
	let customTo = $state('');

	/// Last non-custom value of `dateRange`. Used to bounce back when
	/// the user picks Custom from the dropdown then closes the picker
	/// without committing — without this they'd be stranded in a
	/// "Custom but no bounds" state (which behaves like All time but
	/// reads as Custom in the dropdown). Also used as the effective
	/// range while Custom is selected but bounds are empty.
	let prevNonCustomRange = $state<DateRange>('today');
	$effect(() => {
		if (dateRange !== 'custom') prevNonCustomRange = dateRange;
	});

	/// While the user has picked Custom from the dropdown but hasn't
	/// committed bounds via Apply yet, the filter logic AND the fetch
	/// mode both treat the range as `prevNonCustomRange`. This means
	/// selecting Custom from the dropdown is a no-op against the
	/// underlying runs list — it just opens the picker. Only Apply
	/// (which sets customFrom/customTo) flips the effective range to
	/// 'custom' and triggers the corresponding refetch.
	let effectiveDateRange = $derived<DateRange>(
		dateRange === 'custom' && !customFrom && !customTo ? prevNonCustomRange : dateRange
	);

	/// Pagination only applies in browse mode — All time with NO source
	/// + NO activity narrowing. The moment the user adds a filter, the
	/// list switches to full-fetch and Load More disappears: otherwise
	/// the first 50 rows from the DB might contain only a handful of
	/// matches (e.g. 5 Strava runs in the first 50 by date) and the
	/// user has to keep clicking Load More to walk the whole list.
	/// Filters are still client-side; full-fetch is acceptable because
	/// even a heavy account has <10k runs. Pushing filters to the
	/// fetchRuns query would let us paginate under narrowing — a
	/// backlog item once accounts grow past that bound.
	let fetchMode = $derived<'paginated' | 'full'>(
		effectiveDateRange === 'all' && sourceFilter === 'all' && activityFilter === 'all'
			? 'paginated'
			: 'full'
	);

	/// Filters persist across navigation via localStorage so the user
	/// doesn't have to rebuild their view every time. Hydration happens
	/// once in onMount; after that an effect mirrors any change back
	/// to localStorage. The `filtersHydrated` flag gates the writer so
	/// the SSR/initial defaults don't clobber a saved blob.
	const FILTERS_KEY = 'runs_filters_v1';
	let filtersHydrated = $state(false);

	onMount(() => {
		// Snapshot restore (SvelteKit back-nav) runs BEFORE onMount and
		// sets filtersHydrated=true. Skip the localStorage read in that
		// case — the snapshot is the authoritative source for this
		// paint, and re-reading localStorage here would clobber the
		// user's in-session filter changes.
		if (filtersHydrated) return;
		try {
			const raw = localStorage.getItem(FILTERS_KEY);
			if (raw) {
				const saved = JSON.parse(raw);
				if (saved.sourceFilter) sourceFilter = saved.sourceFilter;
				if (saved.activityFilter) activityFilter = saved.activityFilter;
				if (saved.dateRange) dateRange = saved.dateRange;
				if (typeof saved.customFrom === 'string') customFrom = saved.customFrom;
				if (typeof saved.customTo === 'string') customTo = saved.customTo;
				if (saved.sortKey) sortKey = saved.sortKey;
			}
		} catch (_) {
			/* localStorage may be unavailable / blob may be corrupt — leave defaults */
		}
		filtersHydrated = true;
	});

	$effect(() => {
		if (!filtersHydrated) return;
		try {
			localStorage.setItem(
				FILTERS_KEY,
				JSON.stringify({ sourceFilter, activityFilter, dateRange, customFrom, customTo, sortKey }),
			);
		} catch (_) {
			/* silent */
		}
	});

	/// Lower-bound / upper-bound cutoffs in local time for the selected
	/// range. `null` on either side means "no cutoff on this side".
	function rangeBounds(range: DateRange): { from: Date | null; to: Date | null } {
		const now = new Date();
		switch (range) {
			case 'today': {
				const d = new Date(now);
				d.setHours(0, 0, 0, 0);
				return { from: d, to: null };
			}
			case 'week':
				// Honour the user's `week_start_day` pref so the run list and
				// the dashboard agree on where the week begins. Shares the
				// pure `periodStart` helper that backs the dashboard goal card.
				return { from: periodStart('week', now, weekStartDay), to: null };
			case 'month': {
				const d = new Date(now);
				d.setHours(0, 0, 0, 0);
				d.setDate(d.getDate() - 30);
				return { from: d, to: null };
			}
			case 'year':
				return { from: new Date(now.getFullYear(), 0, 1), to: null };
			case 'custom': {
				const from = customFrom ? new Date(customFrom + 'T00:00:00') : null;
				const to = customTo ? new Date(customTo + 'T23:59:59.999') : null;
				// While the user has picked Custom but hasn't entered any
				// bounds yet, keep the previously-active range applied —
				// otherwise the list flashes to "All time" for the brief
				// moment between selecting Custom in the dropdown and the
				// picker actually rendering / the user choosing dates.
				if (!from && !to) return rangeBounds(prevNonCustomRange);
				return { from, to };
			}
			case 'all':
				return { from: null, to: null };
		}
	}

	// Multi-select + bulk delete. Selection mode is off by default —
	// toggling on replaces the card's link behaviour with a checkbox
	// tap so the user doesn't navigate away mid-selection. Confirm
	// dialog wraps the destructive bulk action; a `deleting` flag
	// keeps the Delete button from double-firing.
	let selecting = $state(false);
	let selected = $state<Set<string>>(new Set());
	let showBulkConfirm = $state(false);
	let deleting = $state(false);

	function toggleSelect(id: string) {
		const next = new Set(selected);
		if (next.has(id)) next.delete(id);
		else next.add(id);
		selected = next;
	}

	function selectAllVisible() {
		selected = new Set(filteredRuns.map((r) => r.id));
	}

	function clearSelection() {
		selected = new Set();
	}

	function exitSelectMode() {
		selecting = false;
		clearSelection();
	}

	async function handleBulkDelete() {
		showBulkConfirm = false;
		if (selected.size === 0 || deleting) return;
		deleting = true;
		const ids = Array.from(selected);
		const { failed } = await deleteRuns(ids);
		// Remove the ones that succeeded from the in-memory list
		// without refetching — keeps the scroll position.
		const failedSet = new Set(failed);
		runs = runs.filter((r) => failedSet.has(r.id) || !selected.has(r.id));
		deleting = false;
		if (failed.length === 0) {
			showToast(
				m(ids.length === 1 ? 'runs.deletedToastOne' : 'runs.deletedToastMany', { count: ids.length }),
				'success',
			);
			exitSelectMode();
		} else {
			showToast(
				m('runs.deletedPartialToast', { deleted: ids.length - failed.length, failed: failed.length }),
				'error',
			);
			selected = failedSet;
		}
	}

	let filteredRuns = $derived.by(() => {
		const { from, to } = rangeBounds(dateRange);
		const out = runs.filter((r) => {
			if (sourceFilter !== 'all' && r.source !== sourceFilter) return false;
			if (activityFilter !== 'all') {
				const type = r.activity_type ?? 'run';
				if (type !== activityFilter) return false;
			}
			const startedAt = new Date(r.started_at);
			if (from && startedAt < from) return false;
			if (to && startedAt > to) return false;
			return true;
		});
		// Sort in-place on the filtered copy so the user's chosen key
		// persists through filter flips. `fastest` uses pace (sec/km);
		// any run shorter than 10 m is kicked to the bottom because the
		// computed pace is meaningless.
		const pace = (r: Run) =>
			r.distance_m < 10 ? Infinity : r.duration_s / (r.distance_m / 1000);
		switch (sortKey) {
			case 'newest':
				out.sort((a, b) => b.started_at.localeCompare(a.started_at));
				break;
			case 'oldest':
				out.sort((a, b) => a.started_at.localeCompare(b.started_at));
				break;
			case 'longest':
				out.sort((a, b) => b.distance_m - a.distance_m);
				break;
			case 'fastest':
				out.sort((a, b) => pace(a) - pace(b));
				break;
		}
		return out;
	});

	// $derived (not plain const) so the m() labels recompute when the locale
	// changes — a top-level const would call m() once at init, capture the
	// pre-load locale, and never update (the live-switch + async-chunk race).
	const sources = $derived<{ value: RunSource | 'all'; label: string }[]>([
		{ value: 'all', label: m('runs.sourceAll') },
		{ value: 'app', label: m('runs.sourceRecorded') },
		{ value: 'strava', label: 'Strava' },
		{ value: 'parkrun', label: 'parkrun' },
		{ value: 'healthkit', label: 'HealthKit' },
	]);

	const activities = $derived<{ value: string; label: string; icon: string }[]>([
		{ value: 'all', label: m('runs.activityAll'), icon: 'apps' },
		{ value: 'run', label: m('runs.activityRun'), icon: 'directions_run' },
		{ value: 'walk', label: m('runs.activityWalk'), icon: 'directions_walk' },
		{ value: 'cycle', label: m('runs.activityCycle'), icon: 'directions_bike' },
		{ value: 'hike', label: m('runs.activityHike'), icon: 'terrain' },
		{ value: 'stroller', label: m('runs.activityStroller'), icon: 'child_friendly' },
	]);

	/// Monotonic generation counter. Every loadInitial() captures the
	/// current value before its async fetch and discards its result if
	/// another loader (or snapshot.restore) bumped the generation in
	/// the meantime. This is what stops back-nav from blowing away
	/// the restored 100-card list with a freshly-fetched 50-card page:
	/// snapshot.restore bumps the generation, so the in-flight
	/// loadInitial that was kicked off on mount aborts on return.
	let fetchGen = $state(0);

	async function loadInitial() {
		loading = true;
		const gen = ++fetchGen;
		let fresh: Run[];
		let nextHasMore: boolean;
		if (fetchMode === 'paginated') {
			fresh = await fetchRuns({ limit: PAGE_SIZE, offset: 0 });
			nextHasMore = fresh.length === PAGE_SIZE;
		} else {
			fresh = await fetchRuns();
			nextHasMore = false;
		}
		if (gen !== fetchGen) return;
		runs = fresh;
		hasMore = nextHasMore;
		loading = false;
	}

	async function loadMore() {
		if (loadingMore || !hasMore) return;
		loadingMore = true;
		const more = await fetchRuns({ limit: PAGE_SIZE, offset: runs.length });
		runs = [...runs, ...more];
		hasMore = more.length === PAGE_SIZE;
		loadingMore = false;
	}

	let settingsLoadedFor = $state<string | null>(null);
	$effect(() => {
		const uid = auth.user?.id;
		if (!uid || settingsLoadedFor === uid) return;
		settingsLoadedFor = uid;
		loadSettings(uid)
			.then((settings) => {
				const wsd = effective<string>(settings, 'week_start_day');
				if (wsd === 'sunday' || wsd === 'monday') weekStartDay = wsd;
			})
			.catch(() => {
				/* leave the monday default — the filter still works */
			});
		// Multi-modal History: pull the unified activities feed so the kind
		// chips + timeline can render once a second modality has data. Loaded
		// INDEPENDENTLY of settings (not chained behind loadSettings) and
		// gated by `activitiesLoaded` so the layout decision is made before
		// first content paint. Without the gate the page paints the run list,
		// then flips to the timeline the moment this feed resolves for a
		// multi-modal account. A pure runner's feed has only runs, so no chips
		// appear and the page stays the run-only history (data-gated, no flag
		// — decisions §63 amendment). Best-effort — a failure just hides the
		// chips. (multi_modal.md § History.)
		fetchActivities(200)
			.then((rows) => (activityFeed = rows))
			.catch(() => {
				/* silent — chips stay hidden, run history unaffected */
			})
			.finally(() => (activitiesLoaded = true));
	});

	// --- Unified activities timeline (multi-modal History) ---
	let activityFeed = $state<ActivityRow[]>([]);
	/// True once the activities feed has resolved (or errored) for the
	/// signed-in user. The layout decision — run list vs unified timeline —
	/// is gated on this so the page doesn't paint the run list and then flip
	/// to the timeline once the feed lands for a multi-modal account.
	let activitiesLoaded = $state(false);
	type KindFilter = 'all' | 'run' | 'lift' | 'meal';
	let kindFilter = $state<KindFilter>('all');

	let hasLift = $derived(activityFeed.some((a) => a.kind === 'lift'));
	let hasMeal = $derived(activityFeed.some((a) => a.kind === 'meal'));
	// Chips only appear once there's a SECOND modality to switch to — a
	// runner who only runs sees no chips (anti-clutter checklist, data-gated).
	let showKindChips = $derived(hasLift || hasMeal);
	/// First-paint gate: we can commit to a layout once the activities feed
	/// has resolved (so we know whether a second modality exists), or once
	/// auth has settled with no signed-in user (nothing to load — render the
	/// run list directly). Until then the page holds a neutral skeleton.
	let activitiesReady = $derived(activitiesLoaded || (!auth.loading && !auth.user));
	// Filter chips for empty kinds are hidden, not disabled.
	let kindChips = $derived.by<{ value: KindFilter; key: MessageKey }[]>(() => {
		const out: { value: KindFilter; key: MessageKey }[] = [
			{ value: 'all', key: 'history.kindAll' },
			{ value: 'run', key: 'history.kindRuns' },
		];
		if (hasLift) out.push({ value: 'lift', key: 'history.kindLifts' });
		if (hasMeal) out.push({ value: 'meal', key: 'history.kindMeals' });
		return out;
	});
	// Client-side filter over the already-fetched window — no round-trip
	// per chip. Activities arrive newest-first from the view.
	let timelineRows = $derived(
		kindFilter === 'all' ? activityFeed : activityFeed.filter((a) => a.kind === kindFilter),
	);
	let timelineGroups = $derived.by(() => {
		const today = new Date();
		today.setHours(0, 0, 0, 0);
		const yesterday = new Date(today);
		yesterday.setDate(yesterday.getDate() - 1);
		const groups: { key: string; label: string; rows: ActivityRow[] }[] = [];
		let cur: { key: string; label: string; rows: ActivityRow[] } | null = null;
		for (const a of timelineRows) {
			const d = new Date(a.started_at);
			d.setHours(0, 0, 0, 0);
			let label: string;
			if (d.getTime() === today.getTime()) label = m('history.today');
			else if (d.getTime() === yesterday.getTime()) label = m('history.yesterday');
			else label = formatDate(a.started_at);
			if (!cur || cur.key !== label) {
				cur = { key: label, label, rows: [] };
				groups.push(cur);
			}
			cur.rows.push(a);
		}
		return groups;
	});
	function activitySummary(a: ActivityRow): { primary: string; secondary: string } {
		const s = a.summary;
		if (a.kind === 'lift') {
			const setCount = typeof s.set_count === 'number' ? s.set_count : 0;
			const vol = typeof s.volume_kg === 'number' ? Math.round(s.volume_kg) : 0;
			const secondary = [m('history.setCount', { n: setCount })];
			// Show volume in the user's weight unit (kg/lbs), matching the mobile
			// timeline + the gym surfaces — not a bare unitless number.
			if (vol > 0) secondary.push(formatWeight(vol));
			return {
				primary: (typeof s.title === 'string' && s.title) || m('gym.untitled'),
				secondary: secondary.join(' · '),
			};
		}
		if (a.kind === 'meal') {
			const kcal = typeof s.calories === 'number' ? Math.round(s.calories) : null;
			return {
				primary: typeof s.item_name === 'string' ? s.item_name : '—',
				secondary: kcal != null ? m('history.kcal', { n: kcal.toLocaleString() }) : '',
			};
		}
		const dist = typeof s.distance_m === 'number' ? s.distance_m : 0;
		const dur = typeof s.duration_s === 'number' ? s.duration_s : 0;
		return {
			primary: formatDistance(dist),
			secondary: dur > 0 ? formatDuration(dur) : '',
		};
	}
	function activityGlyph(kind: ActivityRow['kind']): string {
		return kind === 'lift' ? 'fitness_center' : kind === 'meal' ? 'restaurant' : 'directions_run';
	}
	function activityHref(a: ActivityRow): string | null {
		if (a.kind === 'run') return `/runs/${a.id}`;
		if (a.kind === 'lift') return `/gym/${a.id}`;
		// Meals have no detail route yet (nutrition module pending); the
		// row renders read-only rather than linking to a 404.
		return null;
	}

	$effect(() => {
		// Don't fetch before the auth store has hydrated. fetchRuns
		// reads `auth.user?.id` and returns [] if it's null — which
		// would race on cold loads where the page mounts before the
		// auth cookie is processed and produce a permanent "No runs
		// found" state.
		//
		// Gate on BOTH `auth.loading` and `auth.user` because there's
		// a window where auth.svelte.ts has flipped loading=false
		// (session check is done) but `user` is still null
		// (fetchUser is in flight, profile not yet loaded). The
		// $effect re-fires when auth.user becomes set.
		if (auth.loading || !auth.user) return;
		// Wait for the authoritative state source before firing the
		// initial fetch. On a cold load that's onMount (reads filters
		// from localStorage, sets filtersHydrated=true). On back-nav
		// that's snapshot.restore (also sets filtersHydrated=true plus
		// runs + lastFetchMode from the captured page state). Without
		// this gate, the effect fires with lastFetchMode='' on mount,
		// starts an async loadInitial(), and that async write overwrites
		// the 100 restored cards back to a fresh 50-card page.
		if (!filtersHydrated) return;
		if (fetchMode !== lastFetchMode) {
			lastFetchMode = fetchMode;
			loadInitial();
		}
	});

	/// Preserve the loaded list across in-app navigation so clicking a
	/// run, then `back`, lands the user at the same scroll position
	/// they were at — instead of a flash of "Loading…" plus a jump to
	/// the top. The snapshot has to carry the FILTER values too, not
	/// just runs+hasMore+lastFetchMode. Without filters in the
	/// snapshot, restore would set the list and then onMount() would
	/// re-read filters from localStorage, fetchMode would re-derive,
	/// the `fetchMode !== lastFetchMode` effect would fire loadInitial,
	/// and the restored list would be wiped before the user saw it.
	/// `filtersHydrated = true` in restore also short-circuits the
	/// onMount localStorage read — restore is the authoritative source
	/// for this paint, localStorage is only the fallback for cold loads.
	export const snapshot: Snapshot<{
		runs: Run[];
		hasMore: boolean;
		lastFetchMode: 'paginated' | 'full' | '';
		sourceFilter: RunSource | 'all';
		activityFilter: string;
		sortKey: SortKey;
		dateRange: DateRange;
		customFrom: string;
		customTo: string;
		activityFeed: ActivityRow[];
		activitiesLoaded: boolean;
		kindFilter: KindFilter;
		scrollY: number;
	}> = {
		capture: () => ({
			runs,
			hasMore,
			lastFetchMode,
			sourceFilter,
			activityFilter,
			sortKey,
			dateRange,
			customFrom,
			customTo,
			activityFeed,
			activitiesLoaded,
			kindFilter,
			scrollY: typeof window === 'undefined' ? 0 : window.scrollY,
		}),
		restore: (s) => {
			// Invalidate any in-flight loadInitial that the mount-time
			// fetch-effect already kicked off. Without this the async
			// fetch returns after restore and overwrites the captured
			// runs with a fresh first-page-of-50.
			fetchGen++;
			runs = s.runs;
			hasMore = s.hasMore;
			lastFetchMode = s.lastFetchMode;
			sourceFilter = s.sourceFilter;
			activityFilter = s.activityFilter;
			sortKey = s.sortKey;
			dateRange = s.dateRange;
			customFrom = s.customFrom;
			customTo = s.customTo;
			// Restore the unified-timeline state too so back-nav repaints the
			// same layout (timeline vs run list) without flashing a skeleton
			// or re-flipping while the activities feed refetches.
			activityFeed = s.activityFeed;
			activitiesLoaded = s.activitiesLoaded;
			kindFilter = s.kindFilter;
			filtersHydrated = true;
			loading = false;
			// SvelteKit's auto scroll-restoration runs before our list
			// has had a chance to render, so the page is too short and
			// scroll falls back to 0. After the DOM has updated with
			// the restored cards, re-apply the captured scrollY.
			if (typeof window !== 'undefined' && s.scrollY > 0) {
				queueMicrotask(() => {
					requestAnimationFrame(() => window.scrollTo(0, s.scrollY));
				});
			}
		},
	};

	let showRunModal = $state(false);
	let showRangePicker = $state(false);

	// Modality-aware logging from the unified timeline. The "All" view
	// surfaces a Log menu (run / workout / meal); a single-modality view
	// (Lifts / Meals chip) shows the one matching action directly. The
	// run-list view keeps its own Add-run button — this cluster is hidden
	// there to avoid a duplicate.
	let showWorkoutModal = $state(false);
	let showFoodModal = $state(false);
	let logMenuOpen = $state(false);
	let logMenuTrigger = $state<HTMLButtonElement | null>(null);
	let logMenuPanel = $state<HTMLDivElement | null>(null);

	/// Exercise-name autocomplete for the gym editor, lazily fetched the
	/// first time the workout modal is opened so a workout logged from
	/// History gets the same suggestions as one logged from /gym. Best-
	/// effort — an empty list just means no datalist hints.
	let gymSuggestions = $state<string[]>([]);
	let gymSuggestionsLoaded = $state(false);
	async function ensureGymSuggestions() {
		if (gymSuggestionsLoaded) return;
		gymSuggestionsLoaded = true;
		try {
			const hist = await fetchGymSetHistory();
			const counts = new Map<string, number>();
			for (const s of hist) {
				const name = s.exercise_name.trim();
				if (name === '') continue;
				counts.set(name, (counts.get(name) ?? 0) + 1);
			}
			gymSuggestions = [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([n]) => n);
		} catch (_) {
			/* leave empty — datalist hints are optional */
		}
	}

	function openLog(kind: 'run' | 'workout' | 'meal') {
		logMenuOpen = false;
		if (kind === 'run') {
			showRunModal = true;
		} else if (kind === 'workout') {
			void ensureGymSuggestions();
			showWorkoutModal = true;
		} else {
			showFoodModal = true;
		}
	}

	/// Refetch the unified feed after an in-place log so the new lift/meal
	/// row appears without a full navigation. Best-effort: a failure leaves
	/// the existing feed untouched.
	async function reloadActivities() {
		try {
			activityFeed = await fetchActivities(200);
		} catch (_) {
			/* silent — keep the current feed */
		}
	}

	function onWorkoutCreated() {
		showWorkoutModal = false;
		void reloadActivities();
	}

	function onFoodLogged() {
		showFoodModal = false;
		void reloadActivities();
	}

	onMount(() => {
		function onDocClick(e: MouseEvent) {
			if (!logMenuOpen) return;
			const target = e.target as Node | null;
			if (logMenuPanel?.contains(target ?? null)) return;
			if (logMenuTrigger?.contains(target ?? null)) return;
			logMenuOpen = false;
		}
		function onKeydown(e: KeyboardEvent) {
			if (logMenuOpen && e.key === 'Escape') {
				logMenuOpen = false;
				logMenuTrigger?.focus();
			}
		}
		document.addEventListener('mousedown', onDocClick);
		document.addEventListener('keydown', onKeydown);
		return () => {
			document.removeEventListener('mousedown', onDocClick);
			document.removeEventListener('keydown', onKeydown);
		};
	});

	function handleRangePickerClose(): void {
		showRangePicker = false;
		if (dateRange === 'custom' && !customFrom && !customTo) {
			dateRange = prevNonCustomRange;
		}
	}

	/// Compact label for the toolbar chip when a custom range is set.
	/// "May 1 – May 7" (cross-year picks add the year suffix). The chip
	/// itself is hidden when both bounds are empty, so this function
	/// only runs in states where at least one bound is set.
	function customRangeChipLabel(): string {
		const months = [
			'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
			'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
		];
		const fmt = (s: string) => {
			const d = new Date(s + 'T00:00:00');
			const base = `${months[d.getMonth()]} ${d.getDate()}`;
			return d.getFullYear() === new Date().getFullYear()
				? base
				: `${base}, ${d.getFullYear()}`;
		};
		if (customFrom && customTo) return `${fmt(customFrom)} – ${fmt(customTo)}`;
		if (customFrom) return m('runs.rangeFrom', { date: fmt(customFrom) });
		return m('runs.rangeUntil', { date: fmt(customTo) });
	}

	async function handleRunCreated(run: { id: string }) {
		showRunModal = false;
		// Navigate straight to the new run so the user lands on the
		// detail page they'd otherwise have hit via the standalone form.
		goto(`/runs/${run.id}`);
	}
</script>

<svelte:head>
	<title>{m('history.pageTitle')}</title>
</svelte:head>

<div class="page">
	<!--
		audit/accessibility (May 2026) High — WCAG 1.3.1 + 2.4.6.
		Run-history page needs an h1; visually-hidden because the
		page-header already shows the activity-type toolbar as the
		visual primary surface.
	-->
	<h1 class="visually-hidden">{m('history.heading')}</h1>

	{#snippet listSkeleton()}
		<div class="run-list run-list-skel" aria-hidden="true">
			{#each Array(8) as _, i (i)}
				<div class="skel-card">
					<div class="skel skel-map"></div>
					<div class="skel-card-body">
						<div class="skel-card-top">
							<span class="skel skel-line skel-w-40"></span>
							<span class="skel skel-pill"></span>
						</div>
						<div class="skel-card-stats">
							<div class="skel-card-stat">
								<span class="skel skel-line skel-w-60"></span>
								<span class="skel skel-line skel-w-30"></span>
							</div>
							<div class="skel-card-stat">
								<span class="skel skel-line skel-w-50"></span>
								<span class="skel skel-line skel-w-30"></span>
							</div>
							<div class="skel-card-stat">
								<span class="skel skel-line skel-w-50"></span>
								<span class="skel skel-line skel-w-30"></span>
							</div>
						</div>
					</div>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">{m('runs.loadingRuns')}</p>
	{/snippet}

	{#if !activitiesReady}
		<!-- Hold a neutral skeleton until the activities feed resolves so the
		     page commits to the right layout (run list vs unified timeline) on
		     first content paint instead of painting the run list and flipping
		     to the timeline once the feed lands for a multi-modal account. -->
		{@render listSkeleton()}
	{:else}
	{#if showKindChips}
		<!-- Kind chips — client-side filter over the unified activities
		     view (multi_modal.md § History). Only shown once a second
		     modality exists; chips for empty kinds are hidden. Type is
		     coded by glyph + label inside each timeline row, not by the
		     chip colour, so the chips aren't load-bearing for scanning.
		     The modality-aware Log cluster sits opposite the chips: a menu
		     in the All view, the single matching action under a Lifts/Meals
		     chip. Hidden under the Runs chip — the run-list view below owns
		     its own Add-run button, so showing it here too would duplicate. -->
		<div class="timeline-header">
			<div class="kind-chips seg-group" role="group" aria-label={m('runs.activityTypeGroup')}>
				{#each kindChips as c (c.value)}
					<button
						type="button"
						class="kind-chip seg-btn"
						class:active={kindFilter === c.value}
						aria-pressed={kindFilter === c.value}
						onclick={() => (kindFilter = c.value)}
					>
						{m(c.key)}
					</button>
				{/each}
			</div>

			{#if kindFilter === 'all'}
				<div class="log-menu">
					<button
						bind:this={logMenuTrigger}
						type="button"
						class="add-btn"
						aria-haspopup="menu"
						aria-expanded={logMenuOpen}
						onclick={() => (logMenuOpen = !logMenuOpen)}
					>
						<span class="material-symbols" aria-hidden="true">add</span>
						{m('history.logAction')}
						<span class="material-symbols caret" class:open={logMenuOpen} aria-hidden="true">expand_more</span>
					</button>
					{#if logMenuOpen}
						<div bind:this={logMenuPanel} class="log-menu-panel" role="menu">
							<button type="button" class="log-menu-item" role="menuitem" onclick={() => openLog('run')}>
								<span class="material-symbols" aria-hidden="true">directions_run</span>{m('history.logRun')}
							</button>
							<button type="button" class="log-menu-item" role="menuitem" onclick={() => openLog('workout')}>
								<span class="material-symbols" aria-hidden="true">fitness_center</span>{m('history.logWorkout')}
							</button>
							<button type="button" class="log-menu-item" role="menuitem" onclick={() => openLog('meal')}>
								<span class="material-symbols" aria-hidden="true">restaurant</span>{m('history.logFood')}
							</button>
						</div>
					{/if}
				</div>
			{:else if kindFilter === 'lift'}
				<button type="button" class="add-btn" onclick={() => openLog('workout')}>
					<span class="material-symbols" aria-hidden="true">add</span>
					{m('history.logWorkout')}
				</button>
			{:else if kindFilter === 'meal'}
				<button type="button" class="add-btn" onclick={() => openLog('meal')}>
					<span class="material-symbols" aria-hidden="true">add</span>
					{m('history.logFood')}
				</button>
			{/if}
		</div>
	{/if}

	{#if showKindChips && kindFilter !== 'run'}
		<!-- Unified reverse-chronological timeline over the activities
		     view. Each row taps through to its own detail route; meals
		     have no detail screen yet (nutrition module pending) so they
		     render read-only rather than linking to a 404. -->
		{#if timelineRows.length === 0}
			<div class="card-elevated empty">
				<span class="material-symbols empty-icon" aria-hidden="true">inbox</span>
				<h2 class="empty-text">{m('history.emptyTimeline')}</h2>
			</div>
		{:else}
			<div class="timeline">
				{#each timelineGroups as g (g.key)}
					<section class="timeline-group">
						<h2 class="timeline-day">{g.label}</h2>
						<ul class="timeline-list card-elevated">
							{#each g.rows as a (a.id)}
								{@const sum = activitySummary(a)}
								{@const href = activityHref(a)}
								<li class="timeline-item">
									<svelte:element
										this={href ? 'a' : 'div'}
										href={href ?? undefined}
										class="timeline-row"
										class:timeline-row-link={href != null}
										data-kind={a.kind}
									>
										<span class="timeline-glyph" data-kind={a.kind} aria-hidden="true">
											<span class="material-symbols">{activityGlyph(a.kind)}</span>
										</span>
										<span class="timeline-main">
											<span class="timeline-primary">{sum.primary}</span>
											{#if sum.secondary}
												<span class="timeline-secondary">{sum.secondary}</span>
											{/if}
										</span>
										{#if href}
											<span class="material-symbols timeline-arrow" aria-hidden="true">chevron_right</span>
										{/if}
									</svelte:element>
								</li>
							{/each}
						</ul>
					</section>
				{/each}
			</div>
		{/if}
	{:else}
	<header class="page-header">
		<div class="toolbar">
			<div class="toolbar-filters">
			<div class="activity-group seg-group" role="group" aria-label={m('runs.activityTypeGroup')}>
				{#each activities as act}
					<button
						class="activity-btn seg-btn"
						class:active={activityFilter === act.value}
						onclick={() => (activityFilter = act.value)}
						title={act.label}
						aria-label={act.label}
						aria-pressed={activityFilter === act.value}
						type="button"
					>
						<span class="material-symbols">{act.icon}</span>
						<span class="activity-label">{act.label}</span>
					</button>
				{/each}
			</div>

			<div class="select-group">
				<select bind:value={sourceFilter} class="toolbar-select" aria-label={m('runs.sourceLabel')}>
					{#each sources as src}
						<option value={src.value}>{src.label}</option>
					{/each}
				</select>
				<select
					bind:value={dateRange}
					class="toolbar-select"
					aria-label={m('runs.dateRangeLabel')}
					onchange={() => {
						if (dateRange === 'custom') {
							// Clear any persisted bounds before opening the
							// picker. Without this, a customFrom/customTo
							// left over from an earlier session (or earlier
							// in this session) re-applies the moment Custom
							// is re-selected — the list changes before the
							// user has picked anything. The expectation is
							// that selecting Custom opens an empty picker
							// and the visible list keeps showing the
							// previous (non-custom) range until the user
							// taps Apply.
							customFrom = '';
							customTo = '';
							showRangePicker = true;
						}
					}}
				>
					<option value="all">{m('runs.rangeAllTime')}</option>
					<option value="today">{m('runs.rangeToday')}</option>
					<option value="week">{m('runs.rangeThisWeek')}</option>
					<option value="month">{m('runs.rangeLast30Days')}</option>
					<option value="year">{m('runs.rangeThisYear')}</option>
					<option value="custom">{m('runs.rangeCustom')}</option>
				</select>
				<select bind:value={sortKey} class="toolbar-select" aria-label={m('runs.sortLabel')}>
					<option value="newest">{m('runs.sortNewest')}</option>
					<option value="oldest">{m('runs.sortOldest')}</option>
					<option value="longest">{m('runs.sortLongest')}</option>
					<option value="fastest">{m('runs.sortFastest')}</option>
				</select>
			</div>
			</div>

			<div class="toolbar-actions">
				{#if selecting}
					<button class="link-btn" onclick={selectAllVisible} type="button">{m('runs.selectAll')}</button>
					<button class="link-btn" onclick={exitSelectMode} type="button">{m('runs.done')}</button>
				{:else}
					<a class="link-btn" href="/runs/heatmap">{m('runs.heatmap')}</a>
					<button class="link-btn" onclick={() => (selecting = true)} type="button">{m('runs.select')}</button>
					<button class="add-btn" type="button" onclick={() => (showRunModal = true)}>{m('runs.addRunShort')}</button>
				{/if}
			</div>
		</div>

		{#if dateRange === 'custom' && (customFrom || customTo)}
			<!-- Chip-row only appears once Custom dates are set. The
			     dropdown itself auto-opens the picker on Custom selection
			     (onchange above), so a "Pick dates…" placeholder button
			     below it would just be a second control for the same
			     intent. Once dates are picked the chip shows the range
			     as a status + click-to-edit handle. -->
			<div class="date-picker-row">
				<button
					type="button"
					class="range-chip"
					onclick={() => (showRangePicker = true)}
					aria-label={m('runs.openRangePicker')}
				>
					<span class="material-symbols">calendar_month</span>
					{customRangeChipLabel()}
				</button>
				<button
					type="button"
					class="link-btn"
					onclick={() => {
						customFrom = '';
						customTo = '';
						// Clearing the bounds while still in Custom mode
						// would strand the user in a state where the
						// dropdown reads "Custom…" but the visible list
						// reflects the previous (non-custom) range —
						// inconsistent. Flip dateRange back so the
						// dropdown matches the visible state.
						dateRange = prevNonCustomRange;
					}}>{m('runs.clear')}</button>
			</div>
		{/if}
	</header>

	{#if loading}
		{@render listSkeleton()}
	{:else}
		<div class="run-list">
			{#each filteredRuns as run}
				{@const isSelected = selected.has(run.id)}
				<svelte:element
					this={selecting ? 'button' : 'a'}
					role={selecting ? 'button' : 'link'}
					class="run-card"
					class:selecting
					class:selected={selecting && isSelected}
					class:has-map={!!run.track_url}
					href={selecting ? undefined : `/runs/${run.id}`}
					type={selecting ? 'button' : undefined}
					onclick={selecting ? () => toggleSelect(run.id) : undefined}
				>
					{#if selecting}
						<span
							class="select-box"
							class:checked={isSelected}
							aria-hidden="true"
						>
							{#if isSelected}
								<span class="material-symbols">check</span>
							{/if}
						</span>
					{/if}
					<!-- Always render the map slot so every card has the
						 same height. Cards with a track render the real
						 polyline + tile background; cards without (manual
						 entries, parkrun rows with no GPS) show a subtle
						 placeholder so the grid stays even.
						 Icon ligature is `map` — the outlined variant is
						 already applied via the `material-symbols` class
						 (font family is `Material Symbols Outlined` per
						 app.css). `map_outlined` would render as a
						 missing-icon placeholder. -->
					<div class="run-map-placeholder">
						{#if run.track_url}
							<!-- ownerUserId + runId are passed defensively. The /history
								 page is auth-gated to the viewer's own runs today, so
								 the clip path isn't entered (shouldClip resolves
								 false when ownerUserId === viewerId). Pinning both
								 props keeps the safe shape if the page is ever widened
								 to show another user's runs — without them, the clip
								 gate silently falls open. See audit:privacy-zones
								 2026-05-25 + the corresponding security_guards.test
								 case below. -->
							<RunTrackPreview
								trackUrl={run.track_url}
								runId={run.id}
								ownerUserId={run.user_id}
							/>
						{:else}
							<span class="material-symbols no-track-icon" aria-hidden="true">
								map
							</span>
							<span class="no-track-label">{m('runs.noGpsTrack')}</span>
						{/if}
					</div>
					<div class="run-details">
						<div class="run-top">
							<span class="run-date">{formatDate(run.started_at)}</span>
							<span class="source-badge" style="background: {sourceColor(run.source)}"
								>{sourceLabel(run.source)}</span
							>
						</div>
						<div class="run-stats">
							<div class="run-stat">
								<span class="run-stat-value">{formatDistance(run.distance_m)}</span>
								<span class="run-stat-label section-label">{m('runs.statDistance')}</span>
							</div>
							<div class="run-stat">
								<span class="run-stat-value">{formatDuration(run.duration_s)}</span>
								<span class="run-stat-label section-label">{m('runs.statTime')}</span>
							</div>
							<div class="run-stat">
								<span class="run-stat-value"
									>{formatPace(run.duration_s, run.distance_m)}</span
								>
								<span class="run-stat-label section-label">{m('runs.statPace')}</span>
							</div>
							{#if typeof (run.metadata as Record<string, unknown> | null)?.elevation_m === 'number' && ((run.metadata as Record<string, unknown>).elevation_m as number) > 0}
								<div class="run-stat">
									<span class="run-stat-value"
										>{formatElevation((run.metadata as Record<string, unknown>).elevation_m as number)}</span
									>
									<span class="run-stat-label section-label">{m('runs.statVert')}</span>
								</div>
							{/if}
						</div>
						{#if run.metadata?.event}
							<div class="run-event">
								<span class="material-symbols">event</span>
								<span class="run-event-text">
									{run.metadata.event}{#if run.metadata.position}
										&middot; {m('runs.position', { position: String(run.metadata.position) })}{/if}
								</span>
							</div>
						{/if}
					</div>
				</svelte:element>
			{/each}
		</div>

		{#if selecting && selected.size > 0}
			<div class="bulk-bar" role="toolbar" aria-label={m('runs.selectionActions')}>
				<span class="bulk-count">{m('runs.selectedCount', { count: selected.size })}</span>
				<div class="bulk-actions">
					<button type="button" class="bulk-cancel" onclick={clearSelection}>
						{m('runs.clear')}
					</button>
					<button
						type="button"
						class="bulk-delete"
						disabled={deleting}
						onclick={() => (showBulkConfirm = true)}
					>
						<span class="material-symbols">delete</span>
						{deleting ? m('runs.deleting') : m('runs.delete')}
					</button>
				</div>
			</div>
		{/if}

		<ConfirmDialog
			open={showBulkConfirm}
			title={m(selected.size === 1 ? 'runs.bulkConfirmTitleOne' : 'runs.bulkConfirmTitleMany', { count: selected.size })}
			message={m('runs.bulkConfirmMessage')}
			confirmLabel={m('runs.delete')}
			danger
			onconfirm={handleBulkDelete}
			oncancel={() => (showBulkConfirm = false)}
		/>

		{#if hasMore && fetchMode === 'paginated'}
			<div class="load-more-row">
				<button
					type="button"
					class="btn btn-outline"
					disabled={loadingMore}
					onclick={loadMore}
				>
					{loadingMore ? m('shell.loading') : m('runs.loadMore', { count: PAGE_SIZE })}
				</button>
			</div>
		{/if}

		{#if filteredRuns.length === 0}
			{#if runs.length === 0}
				<div class="card-elevated empty" data-testid="runs-empty-no-data">
					<span class="material-symbols empty-icon" aria-hidden="true">directions_run</span>
					<h2 class="empty-text">{m('runs.emptyNoData')}</h2>
					<p class="empty-hint">
						{m('runs.emptyNoDataHintPrefix')}
						<a href="/settings/integrations">{m('runs.emptyNoDataHintLink')}</a>{m('runs.emptyNoDataHintSuffix')}
					</p>
					<div class="empty-actions">
						<button
							type="button"
							class="btn btn-primary"
							onclick={() => (showRunModal = true)}
						>
							{m('runs.addRun')}
						</button>
					</div>
				</div>
			{:else}
				<div class="card-elevated empty" data-testid="runs-empty-filtered">
					<span class="material-symbols empty-icon" aria-hidden="true">filter_alt_off</span>
					<h2 class="empty-text">{m('runs.emptyFiltered')}</h2>
					<p class="empty-hint">
						{m('runs.emptyFilteredHint')}
					</p>
					<div class="empty-actions">
						<button
							type="button"
							class="btn btn-outline"
							data-testid="runs-empty-show-all"
							onclick={() => {
								dateRange = 'all';
								sourceFilter = 'all';
								activityFilter = 'all';
							}}
						>
							{m('runs.showAllRuns')}
						</button>
						<button type="button" class="btn btn-primary" onclick={() => (showRunModal = true)}>
							{m('runs.addRun')}
						</button>
					</div>
				</div>
			{/if}
		{/if}
	{/if}
	{/if}
	{/if}
</div>

<Modal
	open={showRunModal}
	title={m('runs.addRun')}
	onclose={() => (showRunModal = false)}
>
	<RunEditor oncreated={handleRunCreated} oncancel={() => (showRunModal = false)} />
</Modal>

<Modal
	open={showWorkoutModal}
	title={m('gym.editor.newTitle')}
	onclose={() => (showWorkoutModal = false)}
>
	<GymEditor
		suggestions={gymSuggestions}
		oncreated={onWorkoutCreated}
		oncancel={() => (showWorkoutModal = false)}
	/>
</Modal>

<Modal
	open={showFoodModal}
	title={m('nutrition.logHeading')}
	narrow
	onclose={() => (showFoodModal = false)}
>
	<FoodLogEditor oncreated={onFoodLogged} />
</Modal>

<DateRangePicker
	open={showRangePicker}
	onclose={handleRangePickerClose}
	initialFrom={customFrom}
	initialTo={customTo}
	onapply={(from, to) => {
		customFrom = from;
		customTo = to;
		showRangePicker = false;
	}}
	onclear={() => {
		customFrom = '';
		customTo = '';
	}}
/>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}

	.page-header {
		margin-bottom: var(--space-xl);
	}

	.toolbar {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
	}

	/* The filter cluster (activity segmented control + selects) stays
	   grouped on the left; toolbar-actions push to the right edge. */
	.toolbar-filters {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
	}

	/* Shared segmented-control idiom used by both the activity-type
	   filter (run-list mode) and the kind chips (timeline mode) so the
	   two History modes read as one family. */
	.seg-group {
		display: inline-flex;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		padding: var(--space-2xs);
		gap: var(--space-2xs);
	}

	.seg-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-xs);
		padding: var(--space-xs) var(--space-md);
		border: none;
		border-radius: var(--radius-sm);
		background: transparent;
		font: inherit;
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: background var(--transition-fast), color var(--transition-fast),
			box-shadow var(--transition-fast);
	}
	.seg-btn .material-symbols {
		font-size: 1.05rem;
	}
	.seg-btn:hover {
		color: var(--color-text);
	}
	.seg-btn.active {
		background: var(--color-surface);
		color: var(--color-primary);
		box-shadow: var(--shadow-sm);
	}
	.seg-btn:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}

	.select-group {
		display: inline-flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}

	.toolbar-select {
		padding: var(--space-xs) calc(var(--space-md) + var(--space-md)) var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.85rem;
		font-weight: 500;
		appearance: none;
		background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23999' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><polyline points='6 9 12 15 18 9'/></svg>");
		background-repeat: no-repeat;
		background-position: right var(--space-sm) center;
		background-size: 0.75rem;
		cursor: pointer;
		transition: border-color var(--transition-fast);
	}
	.toolbar-select:hover {
		border-color: var(--color-primary);
	}
	.toolbar-select:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 1px;
	}

	.toolbar-actions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		margin-inline-start: auto;
	}

	@media (max-width: 50rem) {
		.activity-label {
			display: none;
		}
		.toolbar-filters {
			width: 100%;
		}
		.toolbar-actions {
			margin-inline-start: 0;
			width: 100%;
			justify-content: flex-end;
		}
	}

	/* <480px (phone). Stack the toolbar into rows that don't fight for
	   horizontal space and let the selects expand to fill the row. */
	@media (max-width: 30rem) {
		.toolbar {
			gap: var(--space-sm);
		}
		.select-group {
			width: 100%;
		}
		.select-group .toolbar-select {
			flex: 1 1 0;
			min-width: 0;
		}
		.activity-group {
			width: 100%;
			justify-content: space-between;
		}
		.activity-btn {
			flex: 1 1 0;
			justify-content: center;
		}
	}

	.run-list {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: var(--space-md);
	}

	.run-card {
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		overflow: hidden;
		box-shadow: var(--shadow-sm);
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast),
			transform var(--transition-fast);
		text-decoration: none;
		color: inherit;
	}

	.run-card:hover {
		border-color: var(--color-primary);
		box-shadow: var(--shadow-md);
		transform: translateY(-2px);
	}
	.run-card:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.run-map-placeholder {
		width: 100%;
		height: 8rem;
		background: linear-gradient(
			135deg,
			color-mix(in srgb, var(--color-primary) 6%, var(--color-bg-tertiary)),
			var(--color-bg-tertiary) 60%
		);
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0.25rem;
		border-bottom: 1px solid var(--color-border);
	}

	/* The no-track placeholder. Subtle gradient + a map-outline icon
	 * over a small label so the user reads it as "this card just
	 * doesn't have GPS data" rather than "the map failed to load". */
	.run-map-placeholder .no-track-icon {
		font-family: 'Material Symbols Outlined';
		font-size: 1.75rem;
		color: var(--color-text-tertiary);
		opacity: 0.7;
	}
	.run-map-placeholder .no-track-label {
		font-size: 0.7rem;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		font-weight: 600;
	}
	/* RunTrackPreview's own internal map fills the slot — its
	 * inner div takes 100% of this container. */
	.run-map-placeholder :global(.wrap) {
		width: 100%;
		height: 100%;
	}

	.run-details {
		flex: 1;
		min-width: 0;
		padding: var(--space-md) var(--space-lg);
	}

	.run-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-sm);
		gap: var(--space-sm);
	}

	.run-date {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		font-weight: 500;
	}

	/* Source badge — kept inline-styled with the helper's hex to stay
	   consistent with /dashboard, /feed, RunShareView, PeriodSummary,
	   and /runs/[id]. The local rule just controls size, weight, and
	   the slight desaturation that makes it sit quieter on the row. */
	.source-badge {
		font-size: 0.625rem;
		font-weight: 600;
		color: var(--color-surface);
		padding: var(--space-2xs) var(--space-sm);
		border-radius: 9999px;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		white-space: nowrap;
		opacity: 0.92;
	}

	.run-stats {
		display: flex;
		justify-content: space-between;
		gap: var(--space-md);
	}

	.run-stat {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}

	.run-stat-value {
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}

	.run-stat:first-child .run-stat-value {
		font-size: 1.3rem;
		color: var(--color-primary);
	}

	.run-event {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		margin-top: var(--space-md);
		padding-top: var(--space-sm);
		border-top: 1px solid var(--color-border);
		font-size: 0.8rem;
		color: var(--color-text-secondary);
	}
	.run-event .material-symbols {
		font-size: 1rem;
		color: var(--color-text-tertiary);
	}
	.run-event-text {
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.empty {
		grid-column: 1 / -1;
		text-align: center;
		padding: var(--space-2xl) var(--space-md);
		color: var(--color-text-tertiary);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		/* Cap so the card doesn't stretch the full canvas; centred in the
		   grid cell (run-list empties span 1 / -1) and on the timeline. */
		max-width: 32rem;
		margin-inline: auto;
	}
	.empty-icon {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 3.25rem;
		height: 3.25rem;
		border-radius: 50%;
		background: var(--color-bg-tertiary);
		font-size: 1.75rem;
		color: var(--color-text-secondary);
		margin-bottom: var(--space-2xs);
	}
	.empty .empty-text {
		margin: 0;
		font-size: 1.05rem;
		font-weight: 600;
		color: var(--color-text);
		padding: 0;
	}
	.empty-hint {
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		max-width: 28rem;
	}
	.empty-actions {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
		justify-content: center;
		margin-top: var(--space-md);
	}

	.load-more-row {
		display: flex;
		justify-content: center;
		padding: var(--space-md) 0 var(--space-xl);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}

	.date-picker-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
		flex-wrap: wrap;
	}
	.range-chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-xs) var(--space-sm);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.875rem;
		font-weight: 500;
		cursor: pointer;
		transition: border-color var(--transition-fast), background var(--transition-fast);
	}
	.range-chip:hover {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.range-chip .material-symbols {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
	}
	.link-btn {
		background: transparent;
		border: none;
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
		padding: var(--space-xs);
	}
	.link-btn:hover {
		color: var(--color-primary-hover);
	}
	.add-btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-lg);
		background: var(--color-primary);
		color: var(--color-surface);
		border-radius: var(--radius-md);
		font-size: 0.875rem;
		font-weight: 600;
		text-decoration: none;
		border: none;
		cursor: pointer;
		transition: background var(--transition-fast);
	}
	.add-btn:hover { background: var(--color-primary-hover); }

	/* Select-mode renders the card as <button> instead of <a>. Visuals
	   match the link version; the checkbox overlays the corner so the
	   stat grid doesn't reflow. */
	.run-card.selecting {
		position: relative;
		text-align: start;
		cursor: pointer;
		font: inherit;
		color: inherit;
		padding: 0;
		width: 100%;
	}
	.run-card.selecting .run-map-placeholder { pointer-events: none; }
	/* Without a map preview the date row is at the card's top edge where
	   the checkbox sits — inset the date so the box doesn't overlap it.
	   With a map preview the date row is below the thumbnail and needs
	   no inset. */
	.run-card.selecting:not(.has-map) .run-top { padding-inline-start: var(--space-xl); }
	.run-card.selecting.selected {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 2px var(--color-primary-light), var(--shadow-md);
	}
	.select-box {
		position: absolute;
		top: var(--space-sm);
		inset-inline-start: var(--space-sm);
		z-index: 2;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.5rem;
		height: 1.5rem;
		background: var(--color-surface);
		border: 1.5px solid var(--color-border);
		border-radius: var(--radius-sm);
		color: var(--color-surface);
		font-size: 0.95rem;
		font-weight: 700;
		box-shadow: var(--shadow-sm);
		transition: background var(--transition-fast), border-color var(--transition-fast);
	}
	.select-box .material-symbols {
		font-size: 1rem;
		font-weight: 700;
	}
	.select-box.checked {
		background: var(--color-primary);
		border-color: var(--color-primary);
		color: var(--color-surface);
	}

	.bulk-bar {
		position: fixed;
		bottom: var(--space-lg);
		left: 50%;
		transform: translateX(-50%);
		z-index: var(--z-toast);
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-lg);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-lg);
		font-size: 0.95rem;
		min-width: min(28rem, calc(100vw - var(--space-xl)));
	}
	.bulk-count { font-weight: 600; }
	.bulk-actions { display: flex; align-items: center; gap: var(--space-sm); }
	.bulk-cancel {
		padding: var(--space-sm) var(--space-md);
		background: transparent;
		color: var(--color-text);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-weight: 500;
		cursor: pointer;
		transition: background var(--transition-fast);
	}
	.bulk-cancel:hover { background: var(--color-bg-tertiary); }
	.bulk-delete {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-danger);
		color: var(--color-surface);
		border: none;
		border-radius: var(--radius-md);
		font-weight: 600;
		cursor: pointer;
		transition: filter var(--transition-fast);
	}
	.bulk-delete:hover:not(:disabled) { filter: brightness(0.92); }
	.bulk-delete:disabled { opacity: 0.55; cursor: not-allowed; }
	.bulk-delete .material-symbols { font-size: 1.1rem; }

	/* Skeleton placeholder for the initial load. Distinct class (not
	   `.run-card`) so e2e selectors that count run cards don't pick up
	   skeletons in a race. Layout matches the real card so the page
	   renders to its true height immediately — no shift on data arrival. */
	.skel-card {
		display: flex;
		flex-direction: column;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-sm);
		overflow: hidden;
		pointer-events: none;
	}
	/* Mirrors the real card's 8rem map thumbnail so accounts with GPS
	   tracks don't get a height jump when data swaps in. */
	.skel-map {
		width: 100%;
		height: 8rem;
		border-radius: 0;
		border-bottom: 1px solid var(--color-border);
	}
	.skel-card-body { padding: var(--space-md) var(--space-lg); }
	.skel-card-top {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-md);
		gap: var(--space-sm);
	}
	.skel-card-stats {
		display: flex;
		justify-content: space-between;
		gap: var(--space-md);
	}
	.skel-card-stat {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		flex: 1;
	}
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-sm);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-line {
		height: 0.75rem;
	}
	.skel-pill {
		width: 3.5rem;
		height: 1rem;
		border-radius: 9999px;
	}
	.skel-w-30 { width: 30%; }
	.skel-w-40 { width: 40%; }
	.skel-w-50 { width: 50%; }
	.skel-w-60 { width: 60%; }
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	/* .modal-* classes live in app.css. */

	/* --- Unified activities timeline (multi-modal History) --- */
	/* Chips on the leading edge, the modality-aware Log action on the
	   trailing edge — mirrors the /gym and /nutrition headers so the three
	   modalities read as one family. */
	.timeline-header {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
		margin-bottom: var(--space-lg);
	}
	.timeline-header .kind-chips {
		margin-bottom: 0;
	}
	.timeline-header .log-menu,
	.timeline-header > .add-btn {
		margin-inline-start: auto;
	}
	.kind-chips {
		margin-bottom: var(--space-lg);
	}

	.add-btn .caret {
		font-size: 1.05rem;
		transition: transform var(--transition-fast);
	}
	.add-btn .caret.open {
		transform: rotate(180deg);
	}

	/* Action menu for the All-view Log button. Purpose-fit menu (not the
	   listbox ChipDropdown) — each item launches a create modal rather
	   than selecting a persistent value. */
	.log-menu {
		position: relative;
		display: inline-flex;
	}
	.log-menu-panel {
		position: absolute;
		top: calc(100% + 0.3rem);
		inset-inline-end: 0;
		z-index: 60;
		min-width: 12rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.16);
		padding: 0.25rem;
		display: flex;
		flex-direction: column;
		gap: 0.05rem;
	}
	.log-menu-item {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		text-align: start;
		background: transparent;
		border: none;
		font: inherit;
		font-size: 0.9rem;
		color: var(--color-text);
		padding: var(--space-sm) var(--space-sm);
		border-radius: var(--radius-sm);
		cursor: pointer;
	}
	.log-menu-item:hover,
	.log-menu-item:focus-visible {
		background: var(--color-bg-secondary);
		outline: none;
	}
	.log-menu-item .material-symbols {
		font-size: 1.15rem;
		color: var(--color-text-secondary);
	}

	@media (max-width: 30rem) {
		.timeline-header .log-menu,
		.timeline-header > .add-btn {
			margin-inline-start: 0;
		}
		.timeline-header {
			justify-content: space-between;
		}
	}

	/* Day groups flow into a responsive multi-column grid on wide canvases
	   so the timeline fills the page instead of stranding the right ~40% as
	   dead space, while each day card keeps a readable row width. A single
	   full-width column was the original shape but left rows ~40% used; a
	   day-per-cell grid keeps rows dense AND uses the width. Collapses to one
	   column below ~64rem (and on mobile). Most-recent day is top-left;
	   cells read left-to-right, top-to-bottom. */
	.timeline {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(30rem, 1fr));
		gap: var(--space-xl);
		align-items: start;
	}
	.timeline-group {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.timeline-day {
		font-size: 0.75rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--color-text-tertiary);
		margin: 0;
		padding-inline-start: var(--space-2xs);
	}
	/* One elevated panel per day; rows are separated by hairline
	   dividers rather than each being its own bordered box. */
	.timeline-list {
		list-style: none;
		margin: 0;
		padding: 0;
		overflow: hidden;
	}
	.timeline-item + .timeline-item {
		border-top: 1px solid var(--color-border);
	}
	.timeline-row {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		text-decoration: none;
		color: inherit;
		transition: background var(--transition-fast);
	}
	.timeline-row-link:hover { background: var(--color-bg-secondary); }
	.timeline-row-link:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: -2px;
		border-radius: var(--radius-sm);
	}
	/* card-elevated gives the resting shadow + border; zero its default
	   padding so timeline rows fill edge to edge. */
	.timeline-list.card-elevated {
		padding: 0;
	}
	.timeline-glyph {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2.25rem;
		height: 2.25rem;
		border-radius: 50%;
		flex-shrink: 0;
		color: var(--color-text-secondary);
		background: var(--color-bg-tertiary);
	}
	/* Per-kind accent on the glyph chip — a secondary cue; the glyph
	   shape + the row text carry the type, never colour alone. */
	.timeline-glyph[data-kind='lift'] { color: #4e7c5e; background: color-mix(in srgb, #8fbf9f 18%, transparent); }
	.timeline-glyph[data-kind='meal'] { color: #9a6b2f; background: color-mix(in srgb, #d9a25a 20%, transparent); }
	.timeline-glyph[data-kind='run'] { color: var(--color-primary); background: color-mix(in srgb, var(--color-primary) 12%, transparent); }
	.timeline-glyph .material-symbols { font-size: 1.25rem; }
	.timeline-main {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
	}
	.timeline-primary {
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.timeline-secondary {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.timeline-arrow {
		color: var(--color-text-tertiary);
		font-size: 1.2rem;
		flex-shrink: 0;
	}
</style>
