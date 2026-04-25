<script lang="ts">
	import { onMount } from 'svelte';
	import { browseClubs, fetchMyClubs } from '$lib/data';
	import type { ClubWithMeta } from '$lib/types';

	let tab = $state<'browse' | 'mine'>('browse');
	let loading = $state(true);
	let search = $state('');
	let browseResults = $state<ClubWithMeta[]>([]);
	let myClubs = $state<ClubWithMeta[]>([]);

	let visible = $derived(tab === 'browse' ? browseResults : myClubs);

	async function loadBrowse() {
		loading = true;
		browseResults = await browseClubs(search);
		loading = false;
	}

	async function loadMine() {
		loading = true;
		myClubs = await fetchMyClubs();
		loading = false;
	}

	onMount(() => {
		loadMine();
		loadBrowse();
	});

	$effect(() => {
		if (tab === 'browse') loadBrowse();
		if (tab === 'mine') loadMine();
	});

	let searchTimer: ReturnType<typeof setTimeout> | null = null;
	function onSearchInput() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(loadBrowse, 250);
	}
</script>

<div class="page">
	<header class="page-header">
		<div class="title-row">
			<a href="/clubs/new" class="btn-primary">
				<span class="material-symbols">add</span>
				Create club
			</a>
		</div>
		<div class="tabs">
			<button class="tab" class:active={tab === 'browse'} onclick={() => (tab = 'browse')}>
				Browse
			</button>
			<button class="tab" class:active={tab === 'mine'} onclick={() => (tab = 'mine')}>
				My clubs
			</button>
		</div>
		{#if tab === 'browse'}
			<div class="search">
				<span class="material-symbols">search</span>
				<input
					type="search"
					placeholder="Search by name or location"
					bind:value={search}
					oninput={onSearchInput}
				/>
			</div>
		{/if}
	</header>

	{#if loading}
		<p class="muted">Loading…</p>
	{:else if visible.length === 0}
		<div class="empty">
			{#if tab === 'mine'}
				<p>You haven't joined a club yet.</p>
				<button class="btn-secondary" onclick={() => (tab = 'browse')}>Find one to join</button>
			{:else}
				<p>No clubs match that search.</p>
			{/if}
		</div>
	{:else}
		<div class="grid">
			{#each visible as club (club.id)}
				<a href="/clubs/{club.slug}" class="card">
					<div class="card-header">
						<div class="avatar" style="--seed: {hashHue(club.id)}">
							{(club.name[0] ?? '?').toUpperCase()}
						</div>
						<div class="card-title">
							<h3>{club.name}</h3>
							{#if club.location_label}
								<span class="location">
									<span class="material-symbols">place</span>
									{club.location_label}
								</span>
							{/if}
						</div>
						{#if !club.is_public}
							<span class="badge">Private</span>
						{/if}
					</div>
					{#if club.description}
						<p class="desc">{club.description}</p>
					{/if}
					<div class="card-foot">
						<span class="members">
							<span class="material-symbols">group</span>
							{club.member_count} member{club.member_count === 1 ? '' : 's'}
						</span>
						{#if club.viewer_role}
							<span class="chip chip-mine">{club.viewer_role}</span>
						{/if}
					</div>
				</a>
			{/each}
		</div>
	{/if}
</div>

<script module lang="ts">
	function hashHue(id: string): number {
		let h = 0;
		for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
		return Math.abs(h) % 360;
	}
</script>

<style>
	.page {
		max-width: 64rem;
		padding: var(--space-xl) var(--space-2xl);
	}

	.page-header {
		margin-bottom: var(--space-lg);
	}

	.title-row {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		margin-bottom: var(--space-md);
	}

	h1 {
		font-size: 1.75rem;
		font-weight: 700;
	}

	.btn-primary {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		background: var(--color-primary);
		color: var(--color-bg);
		padding: 0.55rem 1rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		font-size: 0.9rem;
	}

	.btn-primary:hover {
		background: var(--color-primary-hover);
	}

	.btn-secondary {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
		padding: 0.5rem 1rem;
		border-radius: var(--radius-md);
		font-weight: 600;
		border: 1px solid var(--color-border);
		cursor: pointer;
	}

	.tabs {
		display: flex;
		gap: 0.5rem;
		margin-bottom: var(--space-md);
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

	.tab.active {
		color: var(--color-primary);
		border-bottom-color: var(--color-primary);
	}

	.search {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.55rem 0.85rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
	}

	.search .material-symbols {
		color: var(--color-text-tertiary);
	}

	.search input {
		border: none;
		background: none;
		flex: 1;
		outline: none;
		font-size: 0.95rem;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
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
	}

	.card:hover {
		transform: translateY(-2px);
		box-shadow: var(--shadow-md);
		border-color: color-mix(in srgb, var(--color-primary) 40%, var(--color-border));
	}

	.card-header {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

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

	.card-title {
		flex: 1;
		min-width: 0;
	}

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

	.location .material-symbols {
		font-size: 0.95rem;
	}

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
	}

	.card-foot {
		display: flex;
		justify-content: space-between;
		align-items: center;
		color: var(--color-text-secondary);
		font-size: 0.85rem;
	}

	.members {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
	}

	.members .material-symbols {
		font-size: 1rem;
	}

	.chip-mine {
		background: var(--color-primary-light);
		color: var(--color-primary);
		padding: 0.15rem 0.55rem;
		border-radius: var(--radius-sm);
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: capitalize;
	}

	.empty {
		text-align: center;
		padding: var(--space-2xl);
		color: var(--color-text-secondary);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 1rem;
	}

	.muted {
		color: var(--color-text-tertiary);
	}
</style>
