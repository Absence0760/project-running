<script lang="ts">
	import { onMount } from 'svelte';
	import {
		searchPeople,
		fetchSuggestedPeople,
		followUser,
		unfollowUser,
		type PeopleSuggestion,
	} from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { showToast } from '$lib/stores/toast.svelte';

	let query = $state('');
	let results = $state<PeopleSuggestion[]>([]);
	let suggestions = $state<PeopleSuggestion[]>([]);
	let searching = $state(false);
	let loadingSuggestions = $state(true);
	let rowBusy = $state<Set<string>>(new Set());

	let searchTimer: ReturnType<typeof setTimeout> | null = null;
	let searchGen = 0;

	let hasQuery = $derived(query.trim().length > 0);
	let visible = $derived(hasQuery ? results : suggestions);

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		try {
			suggestions = await fetchSuggestedPeople(12);
		} finally {
			loadingSuggestions = false;
		}
	});

	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(runSearch, 300);
	}

	async function runSearch() {
		const term = query.trim();
		const gen = ++searchGen;
		if (!term) {
			results = [];
			searching = false;
			return;
		}
		searching = true;
		try {
			const next = await searchPeople(term, 20);
			if (gen !== searchGen) return;
			results = next;
		} catch (e) {
			// Without this catch, a network error during search left
			// the user looking at an empty results list with no
			// feedback. Surface the failure so they know to retry.
			if (gen === searchGen) {
				showToast(`Search failed: ${e}`, 'error');
			}
		} finally {
			if (gen === searchGen) searching = false;
		}
	}

	function clearSearch() {
		query = '';
		results = [];
		searchGen++;
	}

	async function toggleFollow(target: PeopleSuggestion, e: MouseEvent) {
		e.preventDefault();
		e.stopPropagation();
		if (!auth.loggedIn || rowBusy.has(target.id)) return;
		const wasFollowing = target.viewer_follows;
		rowBusy = new Set([...rowBusy, target.id]);
		// Optimistic flip across both result + suggestion lists.
		flipFollow(target.id, !wasFollowing);
		try {
			if (wasFollowing) await unfollowUser(target.id);
			else await followUser(target.id);
		} catch (err) {
			flipFollow(target.id, wasFollowing);
			showToast(`Could not update follow: ${err}`, 'error');
		} finally {
			const next = new Set(rowBusy);
			next.delete(target.id);
			rowBusy = next;
		}
	}

	function flipFollow(id: string, viewer_follows: boolean) {
		results = results.map((r) => (r.id === id ? { ...r, viewer_follows } : r));
		suggestions = suggestions.map((r) => (r.id === id ? { ...r, viewer_follows } : r));
	}

	function initialFor(name: string | null): string {
		return (name?.[0] ?? '?').toUpperCase();
	}

	function hueFor(id: string): number {
		let h = 0;
		for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
		return Math.abs(h) % 360;
	}
</script>

<div class="people">
	<div class="search-wrap">
		<span class="material-symbols" aria-hidden="true">search</span>
		<input
			type="search"
			class="search-input"
			placeholder="Search runners by name"
			bind:value={query}
			oninput={onSearchInput}
			aria-label="Search runners"
		/>
		{#if hasQuery}
			<button
				type="button"
				class="search-clear"
				aria-label="Clear search"
				onclick={clearSearch}
			>
				<span class="material-symbols" aria-hidden="true">close</span>
			</button>
		{/if}
	</div>

	{#if hasQuery}
		<h2 class="section-title">Search results</h2>
		{#if searching}
			<p class="muted" role="status">Searching…</p>
		{:else if results.length === 0}
			<div class="empty-card">
				<span class="material-symbols empty-icon" aria-hidden="true">search_off</span>
				<h3>No runners match "{query.trim()}"</h3>
				<p class="empty-text">
					Try a shorter or different name. Display names are public; people who
					haven't set one yet won't show up here.
				</p>
			</div>
		{/if}
	{:else}
		<h2 class="section-title">Suggested for you</h2>
		{#if loadingSuggestions}
			<div class="grid" aria-hidden="true">
				{#each Array(4) as _, i (i)}
					<div class="skel-row">
						<span class="skel skel-avatar"></span>
						<div class="skel-row-body">
							<span class="skel skel-line skel-w-60"></span>
							<span class="skel skel-line skel-w-40"></span>
						</div>
						<span class="skel skel-btn"></span>
					</div>
				{/each}
			</div>
			<p class="sr-only" role="status">Loading suggestions…</p>
		{:else if suggestions.length === 0}
			<div class="empty-card">
				<span class="material-symbols empty-icon" aria-hidden="true">groups</span>
				<h3>No suggestions yet</h3>
				<p class="empty-text">
					Suggestions come from people in clubs you've joined. Browse clubs to
					find a group near you — once you're in, members show up here.
				</p>
				<a class="btn btn-primary" href="/social?tab=clubs">
					<span class="material-symbols" aria-hidden="true">groups</span>
					Browse clubs
				</a>
			</div>
		{/if}
	{/if}

	{#if visible.length > 0}
		<div class="grid">
			{#each visible as person (person.id)}
				<a class="person-row" href="/u/{person.id}">
					<span
						class="avatar"
						style="--seed: {hueFor(person.id)}"
						aria-hidden="true"
					>
						{#if person.avatar_url}
							<img src={person.avatar_url} alt="" />
						{:else}
							{initialFor(person.display_name)}
						{/if}
					</span>
					<div class="person-body">
						<span class="person-name">{person.display_name ?? 'Runner'}</span>
						<span class="person-meta">
							{person.public_runs_count} public run{person.public_runs_count === 1 ? '' : 's'}
							{#if person.shared_clubs > 0}
								<span class="dot">·</span>
								{person.shared_clubs} club{person.shared_clubs === 1 ? '' : 's'} together
							{/if}
						</span>
					</div>
					{#if auth.loggedIn}
						<button
							type="button"
							class="follow-btn"
							class:following={person.viewer_follows}
							disabled={rowBusy.has(person.id)}
							onclick={(e) => toggleFollow(person, e)}
							aria-label={person.viewer_follows
								? `Unfollow ${person.display_name ?? 'runner'}`
								: `Follow ${person.display_name ?? 'runner'}`}
						>
							<span class="material-symbols" aria-hidden="true">
								{person.viewer_follows ? 'check' : 'person_add'}
							</span>
							<span class="follow-label">
								{person.viewer_follows ? 'Following' : 'Follow'}
							</span>
						</button>
					{/if}
				</a>
			{/each}
		</div>
	{/if}
</div>

<style>
	.people {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.search-wrap {
		position: relative;
		display: flex;
		align-items: center;
		max-width: 32rem;
	}
	.search-wrap > .material-symbols:first-child {
		position: absolute;
		left: 0.75rem;
		color: var(--color-text-tertiary);
		pointer-events: none;
		font-size: 1.1rem;
	}
	.search-input {
		width: 100%;
		padding: 0.55rem 2.25rem 0.55rem 2.25rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.95rem;
	}
	.search-input:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	.search-input:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.search-clear {
		position: absolute;
		right: 0.5rem;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 1.5rem;
		height: 1.5rem;
		padding: 0;
		background: transparent;
		border: none;
		color: var(--color-text-tertiary);
		cursor: pointer;
		border-radius: 50%;
	}
	.search-clear:hover {
		background: var(--color-primary-light);
		color: var(--color-text);
	}
	.search-clear .material-symbols {
		font-size: 1rem;
	}
	.section-title {
		font-size: 0.95rem;
		font-weight: 700;
		color: var(--color-text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.06em;
		margin: var(--space-sm) 0 0;
	}
	.muted {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: var(--space-sm);
	}
	.person-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		text-decoration: none;
		color: inherit;
		transition: transform var(--transition-base), border-color var(--transition-base);
	}
	.person-row:hover {
		transform: translateY(-1px);
		border-color: color-mix(in srgb, var(--color-primary) 35%, var(--color-border));
	}
	.avatar {
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 50%;
		background: hsl(var(--seed, 260), 55%, 55%);
		color: white;
		display: flex;
		align-items: center;
		justify-content: center;
		font-weight: 700;
		font-size: 1.05rem;
		flex-shrink: 0;
		overflow: hidden;
	}
	.avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
	.person-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.person-name {
		font-weight: 600;
		color: var(--color-text);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.person-meta {
		font-size: 0.82rem;
		color: var(--color-text-tertiary);
		display: inline-flex;
		gap: 0.3rem;
		align-items: center;
	}
	.dot {
		opacity: 0.6;
	}
	.follow-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0.3rem 0.75rem;
		font-size: 0.82rem;
		font-weight: 600;
		border-radius: 999px;
		border: 1px solid var(--color-primary);
		background: var(--color-primary);
		color: white;
		cursor: pointer;
	}
	.follow-btn .material-symbols {
		font-size: 1rem;
	}
	.follow-btn.following {
		background: transparent;
		color: var(--color-primary);
	}
	.follow-btn:disabled {
		opacity: 0.6;
		cursor: progress;
	}
	.empty-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-2xl) var(--space-lg);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		text-align: center;
	}
	.empty-card h3 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
	}
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}
	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.material-symbols {
		font-family: 'Material Symbols Outlined';
	}
	.skel-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}
	.skel-row-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-avatar {
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 50%;
		flex-shrink: 0;
	}
	.skel-line { height: 0.75rem; }
	.skel-w-40 { width: 40%; }
	.skel-w-60 { width: 60%; }
	.skel-btn {
		width: 5.5rem;
		height: 1.75rem;
		border-radius: 999px;
	}
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
</style>
