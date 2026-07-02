<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { formatDistance } from '$lib/core/mock-data';
	import { formatDate, formatDuration } from '$lib/format/time';
	import {
		fetchActivities,
		fetchActivitiesWithError,
		fetchGymExerciseNames,
		type ActivityRow,
	} from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import RunEditor from '$lib/components/RunEditor.svelte';
	import GymEditor from '$lib/components/GymEditor.svelte';
	import FoodLogEditor from '$lib/components/FoodLogEditor.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { goto } from '$app/navigation';
	import { formatWeight } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { MessageKey } from '$lib/i18n/messages';
	import type { Snapshot } from './$types';

	// The unified, cross-modal History timeline (multi_modal.md § History).
	// The full run-list management surface lives at /runs (parallel to /gym +
	// /nutrition); this page is the reverse-chronological read view over the
	// `activities` view, with one consistent header per tab. See decisions §63
	// amendment.
	let activityFeed = $state<ActivityRow[]>([]);
	/// True once the activities feed has resolved (or errored) for the
	/// signed-in user. The page holds a neutral skeleton until then so it
	/// commits to its layout (which chips exist) on first content paint
	/// instead of flickering as the feed lands.
	let activitiesLoaded = $state(false);
	/// Non-null only on a real fetch failure. Previously the feed swallowed
	/// errors into an empty timeline, so a transient network / DB failure was
	/// indistinguishable from a genuinely-empty history and rendered the
	/// "nothing logged yet" state with no retry. See fetchActivitiesWithError.
	let loadError = $state<string | null>(null);
	type KindFilter = 'all' | 'run' | 'lift' | 'meal';
	let kindFilter = $state<KindFilter>('all');

	let hasLift = $derived(activityFeed.some((a) => a.kind === 'lift'));
	let hasMeal = $derived(activityFeed.some((a) => a.kind === 'meal'));
	// Chips only appear once there's a SECOND modality to switch to — a
	// runner who only runs sees no chips (anti-clutter checklist, data-gated).
	let showKindChips = $derived(hasLift || hasMeal);
	/// First-paint gate: commit to a layout once the activities feed has
	/// resolved, or once auth has settled with no signed-in user.
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

	let activitiesLoadedFor = $state<string | null>(null);
	/// Set by snapshot.restore on back-nav so the mount-time fetch effect
	/// doesn't refetch and clobber the restored feed (+ scroll position).
	/// restore() runs before auth has settled, so we can't gate on the
	/// user id alone — `activitiesLoadedFor` would be null at that point and
	/// the effect would re-fire the moment auth.user lands.
	let restoredFeed = $state(false);
	/// Monotonic counter: a late-resolving fetch whose generation was bumped
	/// (by restore or a newer fetch) discards its result instead of
	/// overwriting the current feed.
	let fetchGen = $state(0);
	// Pull the unified activities feed (windowed to the most recent 200). The
	// full per-modality history lives on /runs, /gym, /nutrition; the "View
	// all" link on each single-modality tab points there. Surfaces a real
	// failure as a retryable error card instead of an empty timeline (which
	// would read as "nothing logged" and hide the retry). (multi_modal.md
	// § History.)
	function loadActivities() {
		loadError = null;
		activitiesLoaded = false;
		const gen = ++fetchGen;
		fetchActivitiesWithError(200)
			.then((res) => {
				if (gen !== fetchGen) return;
				if (res.error) loadError = res.error;
				else activityFeed = res.activities;
			})
			.catch((e) => {
				if (gen === fetchGen) loadError = (e as Error)?.message ?? 'Failed to load history';
			})
			.finally(() => {
				if (gen === fetchGen) activitiesLoaded = true;
			});
	}

	$effect(() => {
		const uid = auth.user?.id;
		if (!uid || restoredFeed || activitiesLoadedFor === uid) return;
		activitiesLoadedFor = uid;
		loadActivities();
	});

	// --- Modality-aware logging ---
	// The All view surfaces a Log menu (run / workout / meal); a single-
	// modality tab (Runs / Lifts / Meals) shows the one matching action plus a
	// "View all" link to that modality's dedicated page (/runs, /gym,
	// /nutrition). This keeps every tab's top section the same shape.
	let showRunModal = $state(false);
	let showWorkoutModal = $state(false);
	let showFoodModal = $state(false);
	let logMenuOpen = $state(false);
	let logMenuTrigger = $state<HTMLButtonElement | null>(null);
	let logMenuPanel = $state<HTMLDivElement | null>(null);

	/// Per-tab action descriptor for a single-modality view. `null` in the
	/// All view, which uses the Log menu instead.
	let singleAction = $derived.by<
		{ href: string; label: string; kind: 'run' | 'workout' | 'meal' } | null
	>(() => {
		if (kindFilter === 'run') return { href: '/runs', label: m('history.logRun'), kind: 'run' };
		if (kindFilter === 'lift') return { href: '/gym', label: m('history.logWorkout'), kind: 'workout' };
		if (kindFilter === 'meal') return { href: '/nutrition', label: m('history.logFood'), kind: 'meal' };
		return null;
	});

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
			// Distinct names come straight from the server (most-used first)
			// instead of pulling the whole set history just to count them.
			gymSuggestions = await fetchGymExerciseNames();
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

	/// Refetch the unified feed after an in-place log so the new row appears
	/// without a full navigation. Best-effort: a failure leaves the feed as-is.
	/// Bumps the fetch generation so it wins over (and isn't clobbered by) any
	/// in-flight mount-time fetch.
	async function reloadActivities() {
		const gen = ++fetchGen;
		try {
			const rows = await fetchActivities(200);
			if (gen === fetchGen) activityFeed = rows;
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

	async function handleRunCreated(run: { id: string }) {
		showRunModal = false;
		// Navigate straight to the new run so the user lands on the
		// detail page they'd otherwise have hit via the standalone form.
		goto(`/runs/${run.id}`);
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

	// --- Log menu keyboard support (ARIA menu-button pattern) ---
	function logMenuItems(): HTMLButtonElement[] {
		return logMenuPanel
			? Array.from(logMenuPanel.querySelectorAll<HTMLButtonElement>('[role="menuitem"]'))
			: [];
	}
	function focusLogItem(i: number) {
		const items = logMenuItems();
		if (items.length === 0) return;
		items[(i + items.length) % items.length]?.focus();
	}
	async function toggleLogMenu() {
		logMenuOpen = !logMenuOpen;
		if (logMenuOpen) {
			// Move focus into the menu so arrow keys + Escape work immediately.
			await tick();
			focusLogItem(0);
		}
	}
	/// Roving focus among the three menu items. Items stay tabbable too (Tab
	/// still works); this just adds the arrow/Home/End navigation the menu
	/// role implies. Escape is handled by the document listener above.
	function onLogMenuKeydown(e: KeyboardEvent) {
		const items = logMenuItems();
		if (items.length === 0) return;
		const cur = items.indexOf(document.activeElement as HTMLButtonElement);
		if (e.key === 'ArrowDown') {
			e.preventDefault();
			focusLogItem(cur + 1);
		} else if (e.key === 'ArrowUp') {
			e.preventDefault();
			focusLogItem(cur - 1);
		} else if (e.key === 'Home') {
			e.preventDefault();
			focusLogItem(0);
		} else if (e.key === 'End') {
			e.preventDefault();
			focusLogItem(items.length - 1);
		}
	}

	/// Preserve the loaded feed + active tab + scroll position across in-app
	/// navigation so tapping a row then `back` lands where the user was,
	/// instead of a skeleton flash and a jump to the top.
	export const snapshot: Snapshot<{
		activityFeed: ActivityRow[];
		activitiesLoaded: boolean;
		kindFilter: KindFilter;
		scrollY: number;
	}> = {
		capture: () => ({
			activityFeed,
			activitiesLoaded,
			kindFilter,
			scrollY: typeof window === 'undefined' ? 0 : window.scrollY,
		}),
		restore: (s) => {
			// Invalidate any in-flight mount-time fetch the fresh instance may
			// have kicked off before restore ran, then mark the feed restored so
			// the fetch effect stays out — gating on the user id alone is unsafe
			// because auth hasn't settled yet at restore time (auth.user is null,
			// so activitiesLoadedFor would be null and the effect would re-fire
			// the moment auth lands, clobbering the restored feed + scroll).
			fetchGen++;
			restoredFeed = true;
			activityFeed = s.activityFeed;
			activitiesLoaded = s.activitiesLoaded;
			kindFilter = s.kindFilter;
			activitiesLoadedFor = auth.user?.id ?? null;
			if (typeof window !== 'undefined' && s.scrollY > 0) {
				queueMicrotask(() => {
					requestAnimationFrame(() => window.scrollTo(0, s.scrollY));
				});
			}
		},
	};
</script>

<svelte:head>
	<title>{m('history.timelineTitle')}</title>
</svelte:head>

<div class="page">
	<!--
		audit/accessibility (May 2026) High — WCAG 1.3.1 + 2.4.6.
		The timeline needs an h1; visually-hidden because the chip
		toolbar already reads as the visual primary surface.
	-->
	<h1 class="visually-hidden">{m('history.timelineHeading')}</h1>

	{#snippet timelineSkeleton()}
		<div class="timeline timeline-skel" aria-hidden="true">
			{#each Array(2) as _, g (g)}
				<div class="timeline-group">
					<span class="skel skel-line skel-day"></span>
					<ul class="timeline-list card-elevated">
						{#each Array(4) as _, i (i)}
							<li class="timeline-item">
								<span class="skel skel-glyph"></span>
								<span class="skel-rows">
									<span class="skel skel-line skel-w-50"></span>
									<span class="skel skel-line skel-w-30"></span>
								</span>
							</li>
						{/each}
					</ul>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">{m('runs.loadingRuns')}</p>
	{/snippet}

	{#if !activitiesReady}
		{@render timelineSkeleton()}
	{:else}
		<!-- One consistent header per tab: kind chips on the leading edge (only
		     once a second modality exists), and a trailing action cluster — the
		     Log menu in the All view, or a "View all" link + the single Log
		     action under a Runs / Lifts / Meals tab. Mirrors the /gym + /nutrition
		     headers so the modalities read as one family. -->
		<div class="timeline-header">
			{#if showKindChips}
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
			{/if}

			<div class="timeline-actions">
				{#if singleAction}
					<a class="view-all-link" href={singleAction.href}>
						{m('history.viewAll')}
						<span class="material-symbols" aria-hidden="true">chevron_right</span>
					</a>
					<button type="button" class="add-btn" onclick={() => openLog(singleAction.kind)}>
						<span class="material-symbols" aria-hidden="true">add</span>
						{singleAction.label}
					</button>
				{:else}
					<div class="log-menu">
						<button
							bind:this={logMenuTrigger}
							type="button"
							class="add-btn"
							aria-haspopup="menu"
							aria-expanded={logMenuOpen}
							onclick={toggleLogMenu}
							onkeydown={(e) => {
								if (!logMenuOpen && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
									e.preventDefault();
									void toggleLogMenu();
								}
							}}
						>
							<span class="material-symbols" aria-hidden="true">add</span>
							{m('history.logAction')}
							<span class="material-symbols caret" class:open={logMenuOpen} aria-hidden="true">expand_more</span>
						</button>
						{#if logMenuOpen}
							<div bind:this={logMenuPanel} class="log-menu-panel" role="menu" tabindex="-1" onkeydown={onLogMenuKeydown}>
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
				{/if}
			</div>
		</div>

		{#if loadError}
			<div class="card-elevated empty load-error" role="alert" data-testid="history-load-error">
				<span class="material-symbols empty-icon" aria-hidden="true">error</span>
				<h2 class="empty-text">{m('history.loadFailed')}</h2>
				<p class="empty-hint load-error-detail">{loadError}</p>
				<button
					type="button"
					class="btn btn-primary"
					data-testid="history-load-error-retry"
					onclick={() => loadActivities()}
				>
					{m('history.retry')}
				</button>
			</div>
		{:else if timelineRows.length === 0}
			<div class="card-elevated empty">
				<span class="material-symbols empty-icon" aria-hidden="true">inbox</span>
				<h2 class="empty-text">{m('history.emptyTimeline')}</h2>
			</div>
		{:else}
			<!-- Unified reverse-chronological timeline over the activities view.
			     Each row taps through to its own detail route; meals have no
			     detail screen yet (nutrition module pending) so they render
			     read-only rather than linking to a 404. -->
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

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined';
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

	/* --- Header (chips + modality-aware action) --- */
	/* Chips on the leading edge, the action cluster on the trailing edge —
	   mirrors the /gym and /nutrition headers so the modalities read as one
	   family. */
	.timeline-header {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		flex-wrap: wrap;
		margin-bottom: var(--space-lg);
	}

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

	.timeline-actions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		margin-inline-start: auto;
	}

	.view-all-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-primary);
		font-size: 0.85rem;
		font-weight: 600;
		text-decoration: none;
		padding: var(--space-xs);
	}
	.view-all-link:hover {
		color: var(--color-primary-hover);
	}
	.view-all-link .material-symbols {
		font-size: 1.05rem;
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
	.add-btn .material-symbols { font-size: 1.05rem; }
	.add-btn .caret {
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
		.timeline-header {
			justify-content: space-between;
		}
		.timeline-actions {
			margin-inline-start: 0;
		}
	}

	/* --- Timeline --- */
	/* Day groups flow into a responsive multi-column grid on wide canvases
	   so the timeline fills the page instead of stranding the right ~40% as
	   dead space, while each day card keeps a readable row width. Collapses to
	   one column below ~64rem (and on mobile). Most-recent day is top-left;
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

	/* --- Empty + skeleton --- */
	.empty {
		text-align: center;
		padding: var(--space-2xl) var(--space-md);
		color: var(--color-text-tertiary);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
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
		margin: 0;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		max-width: 28rem;
	}
	.load-error .empty-icon {
		background: rgba(239, 68, 68, 0.12);
		color: #ef4444;
	}
	.load-error-detail {
		font-size: 0.78rem;
		word-break: break-word;
	}
	.load-error .btn {
		margin-top: var(--space-sm);
	}

	/* Skeleton mirrors the timeline shape so the page renders to roughly its
	   true height immediately — no shift when the feed lands. */
	.timeline-skel .timeline-item {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-sm) var(--space-md);
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
	.skel-line { height: 0.75rem; }
	.skel-day { width: 6rem; height: 0.7rem; }
	.skel-glyph {
		width: 2.25rem;
		height: 2.25rem;
		border-radius: 50%;
		flex-shrink: 0;
	}
	.skel-rows {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.skel-w-30 { width: 30%; }
	.skel-w-50 { width: 50%; }
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}

	/* .modal-* + .card-elevated classes live in app.css. */
</style>
