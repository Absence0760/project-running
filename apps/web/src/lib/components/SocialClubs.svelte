<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { browseClubs, fetchMyClubs, searchClubs } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import ClubEditor from '$lib/components/ClubEditor.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import VerifiedBadge from '$lib/components/VerifiedBadge.svelte';
	import type { ClubWithMeta } from '$lib/types';

	let subtab = $state<'browse' | 'mine'>('mine');
	let loading = $state(true);
	let search = $state('');
	let browseResults = $state<ClubWithMeta[]>([]);
	let myClubs = $state<ClubWithMeta[]>([]);
	let browseGen = $state(0);
	let mineGen = $state(0);

	let visible = $derived(subtab === 'browse' ? browseResults : myClubs);

	async function loadBrowse() {
		loading = true;
		const gen = ++browseGen;
		// `searchClubs` geocodes the query first (so "Virginia" pulls
		// clubs in Virginia even when their label is "Richmond, VA")
		// and falls back to plain ILIKE when the geocode doesn't
		// resolve. Empty / blank query → plain "most recent 60".
		const result = search.trim()
			? await searchClubs(search)
			: await browseClubs();
		if (gen !== browseGen) return;
		browseResults = result;
		loading = false;
	}

	async function loadMine() {
		loading = true;
		const gen = ++mineGen;
		const result = await fetchMyClubs();
		if (gen !== mineGen) return;
		myClubs = result;
		loading = false;
	}

	function setSubtab(next: 'browse' | 'mine') {
		subtab = next;
		// /social hosts this tab, so the subtab URL key is `clubs-sub` to
		// avoid colliding with the top-level `?tab=clubs`.
		const url = new URL($page.url);
		if (next === 'mine') url.searchParams.delete('clubs-sub');
		else url.searchParams.set('clubs-sub', next);
		goto(url, { replaceState: true, noScroll: true, keepFocus: true });
	}

	onMount(async () => {
		const initial = $page.url.searchParams.get('clubs-sub');
		if (initial === 'browse') subtab = 'browse';

		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (myClubs.length === 0) loadMine();
		if (browseResults.length === 0) loadBrowse();
	});

	let searchTimer: ReturnType<typeof setTimeout> | null = null;
	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(loadBrowse, 250);
	}

	let showClubModal = $state(false);

	function handleClubCreated(club: { slug: string }) {
		showClubModal = false;
		goto(`/clubs/${club.slug}`);
	}

	function hashHue(id: string): number {
		let h = 0;
		for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
		return Math.abs(h) % 360;
	}
</script>

<div class="clubs-panel">
	<div class="tabs" role="tablist" aria-label="Clubs section">
		<button
			role="tab"
			class="tab"
			class:active={subtab === 'mine'}
			aria-selected={subtab === 'mine'}
			onclick={() => setSubtab('mine')}
		>
			My clubs
		</button>
		<button
			role="tab"
			class="tab"
			class:active={subtab === 'browse'}
			aria-selected={subtab === 'browse'}
			onclick={() => setSubtab('browse')}
		>
			Browse
		</button>
	</div>

	<div class="filter-row">
		{#if subtab === 'browse'}
			<div class="search-wrap">
				<span class="material-symbols" aria-hidden="true">search</span>
				<input
					type="text"
					class="search-input"
					placeholder="Search by name or location"
					bind:value={search}
					oninput={onSearchInput}
					aria-label="Search clubs"
				/>
				{#if search}
					<button
						type="button"
						class="search-clear"
						aria-label="Clear search"
						onclick={() => { search = ''; loadBrowse(); }}
					>
						<span class="material-symbols" aria-hidden="true">close</span>
					</button>
				{/if}
			</div>
		{/if}
		<div class="toolbar-actions">
			<button class="btn btn-primary btn-sm" type="button" onclick={() => (showClubModal = true)}>
				<span class="material-symbols" aria-hidden="true">add</span>
				Create club
			</button>
		</div>
	</div>

	{#if loading}
		<div class="grid" aria-hidden="true">
			{#each Array(6) as _, i (i)}
				<div class="skel-card">
					<div class="skel-card-header">
						<span class="skel skel-avatar"></span>
						<div class="skel-card-title">
							<span class="skel skel-line skel-w-60"></span>
							<span class="skel skel-line skel-w-40"></span>
						</div>
					</div>
					<span class="skel skel-line skel-w-80"></span>
					<span class="skel skel-line skel-w-60"></span>
				</div>
			{/each}
		</div>
		<p class="sr-only" role="status">Loading clubs…</p>
	{:else if visible.length === 0}
		<div class="empty-card">
			{#if subtab === 'mine'}
				<img src="/icon-192.png" alt="" width="64" height="64" class="empty-mark" />
				<h3>You haven't joined a club yet</h3>
				<p class="empty-text">
					Clubs are weekly groups, route-sharing circles, and event hubs. Browse
					what's public near you, request to join with one tap, or start your own.
				</p>
				<div class="empty-actions">
					<button class="btn btn-primary" type="button" onclick={() => setSubtab('browse')}>
						<span class="material-symbols" aria-hidden="true">search</span>
						Find a club
					</button>
					<button class="btn btn-outline" type="button" onclick={() => (showClubModal = true)}>
						<span class="material-symbols" aria-hidden="true">add</span>
						Create one instead
					</button>
				</div>
			{:else if search.trim()}
				<span class="material-symbols empty-icon" aria-hidden="true">search_off</span>
				<h3>No clubs match "{search.trim()}"</h3>
				<p class="empty-text">
					Public clubs are searched by name and location. Try a shorter or
					different term, or clear the search to see everything available.
				</p>
				<div class="empty-actions">
					<button
						type="button"
						class="btn btn-primary"
						onclick={() => { search = ''; loadBrowse(); }}
					>
						Clear search
					</button>
				</div>
			{:else}
				<span class="material-symbols empty-icon" aria-hidden="true">groups</span>
				<h3>No public clubs yet</h3>
				<p class="empty-text">
					There aren't any public clubs to browse right now. Start one to put your
					area on the map — others can find and join.
				</p>
				<div class="empty-actions">
					<button class="btn btn-primary" type="button" onclick={() => (showClubModal = true)}>
						<span class="material-symbols" aria-hidden="true">add</span>
						Create a club
					</button>
				</div>
			{/if}
		</div>
	{:else}
		<div class="grid">
			{#each visible as club (club.id)}
				<a href="/clubs/{club.slug}" class="card">
					<div class="card-header">
						<div class="avatar" style="--seed: {hashHue(club.id)}" aria-hidden="true">
							{(club.name[0] ?? '?').toUpperCase()}
						</div>
						<div class="card-title">
							<h3>
									{club.name}
									{#if club.is_verified}
										<VerifiedBadge />
									{/if}
								</h3>
							{#if club.location_label}
								<span class="location">
									<span class="material-symbols" aria-hidden="true">place</span>
									{club.location_label}
								</span>
							{/if}
						</div>
						{#if !club.is_public}
							<span class="badge" title="Private — invite only">Private</span>
						{/if}
					</div>
					{#if club.description}
						<p class="desc">{club.description}</p>
					{/if}
					<div class="card-foot">
						<span class="members">
							<span class="material-symbols" aria-hidden="true">group</span>
							{club.member_count} member{club.member_count === 1 ? '' : 's'}
						</span>
						{#if club.viewer_role}
							<span class="chip chip-mine">{club.viewer_role}</span>
						{:else if club.viewer_status === 'pending'}
							<span class="chip chip-pending" title="Request awaiting admin approval">
								Request pending
							</span>
						{/if}
					</div>
				</a>
			{/each}
		</div>
	{/if}
</div>

<Modal
	open={showClubModal}
	title="Create a club"
	onclose={() => (showClubModal = false)}
>
	<ClubEditor oncreated={handleClubCreated} oncancel={() => (showClubModal = false)} />
</Modal>

<style>
	.clubs-panel {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.tabs {
		display: flex;
		gap: 0.5rem;
		border-bottom: 1px solid var(--color-border);
	}
	.tab {
		background: none;
		border: none;
		padding: 0.6rem 0.2rem;
		margin-right: 1rem;
		font-size: 0.95rem;
		color: var(--color-text-secondary);
		border-bottom: 2px solid transparent;
		cursor: pointer;
		font-weight: 500;
	}
	.tab:hover { color: var(--color-text); }
	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}
	.filter-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm) var(--space-md);
		flex-wrap: wrap;
	}
	.search-wrap {
		position: relative;
		display: flex;
		align-items: center;
		flex: 1 1 18rem;
		min-width: 12rem;
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
		padding: 0.5rem 2.25rem 0.5rem 2.25rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
	}
	.search-input:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
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
	.search-clear .material-symbols { font-size: 1rem; }
	.toolbar-actions {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
		margin-left: auto;
	}
	.toolbar-actions .btn {
		display: inline-flex;
		align-items: center;
		gap: var(--space-xs);
	}
	.toolbar-actions .material-symbols { font-size: 1.05rem; }
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
		gap: var(--space-md);
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		transition:
			transform var(--transition-base),
			box-shadow var(--transition-base),
			border-color var(--transition-base);
		color: inherit;
		text-decoration: none;
	}
	.card:hover {
		transform: translateY(-2px);
		box-shadow: var(--shadow-md);
		border-color: color-mix(in srgb, var(--color-primary) 40%, var(--color-border));
	}
	.card-header { display: flex; align-items: center; gap: 0.75rem; }
	.avatar {
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 50%;
		background: hsl(var(--seed, 260), 50%, 55%);
		color: white;
		display: flex;
		align-items: center;
		justify-content: center;
		font-weight: 700;
		font-size: 1.1rem;
		flex-shrink: 0;
	}
	.card-title { flex: 1; min-width: 0; }
	.card-title h3 {
		font-size: 1.05rem;
		font-weight: 700;
		margin: 0 0 0.15rem 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.location {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		color: var(--color-text-secondary);
		font-size: 0.8rem;
	}
	.location .material-symbols { font-size: 0.95rem; }
	.badge {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
		background: var(--color-bg-tertiary);
		padding: 0.15rem 0.5rem;
		border-radius: var(--radius-sm);
	}
	.desc {
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		line-height: 1.4;
		overflow: hidden;
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		line-clamp: 2;
	}
	.card-foot {
		display: flex;
		justify-content: space-between;
		align-items: center;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}
	.members { display: inline-flex; align-items: center; gap: 0.3rem; }
	.members .material-symbols { font-size: 1rem; }
	.chip-mine {
		background: var(--color-primary-light);
		color: var(--color-primary);
		padding: 0.15rem 0.55rem;
		border-radius: var(--radius-sm);
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: capitalize;
	}
	.chip-pending {
		background: color-mix(in srgb, var(--color-warning) 18%, transparent);
		color: color-mix(in srgb, var(--color-warning) 80%, var(--color-text));
		padding: 0.15rem 0.55rem;
		border-radius: var(--radius-sm);
		font-size: 0.75rem;
		font-weight: 600;
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
	.empty-card h3 { margin: 0; font-size: 1.1rem; font-weight: 600; }
	.empty-icon {
		font-size: 2.5rem;
		color: var(--color-text-tertiary);
		opacity: 0.85;
	}
	.empty-mark {
		display: block;
		border-radius: var(--radius-md);
		box-shadow: var(--shadow-sm);
	}
	.empty-text {
		max-width: 36rem;
		margin: 0;
		font-size: 0.9rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
	}
	.empty-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: var(--space-sm);
		margin-top: var(--space-sm);
	}
	.empty-actions .material-symbols { font-size: 1.1rem; }
	.material-symbols { font-family: 'Material Symbols Outlined'; }
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
	.skel-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		pointer-events: none;
	}
	.skel-card-header {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		margin-bottom: 0.2rem;
	}
	.skel-avatar {
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 50%;
		flex-shrink: 0;
	}
	.skel-card-title {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.skel-line { height: 0.75rem; }
	.skel-w-40 { width: 40%; }
	.skel-w-60 { width: 60%; }
	.skel-w-80 { width: 80%; }
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
	@media (max-width: 50rem) {
		.toolbar-actions { margin-left: 0; width: 100%; justify-content: flex-end; }
		.search-wrap { flex-basis: 100%; }
	}
	@media (max-width: 30rem) {
		.toolbar-actions .btn { flex: 1 1 0; justify-content: center; }
	}
</style>
