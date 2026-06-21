<script lang="ts">
	import { fetchChallenges } from '$lib/core/data';
	import type { ChallengeWithMeta } from '$lib/types';
	import ChallengeEditor from '$lib/components/ChallengeEditor.svelte';
	import ChallengeProgressBar from '$lib/components/ChallengeProgressBar.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { goto } from '$app/navigation';

	let all = $state<ChallengeWithMeta[] | null>(null);
	let creating = $state(false);

	async function load() {
		try {
			all = await fetchChallenges();
		} catch {
			all = [];
		}
	}
	$effect(() => {
		load();
	});

	const mine = $derived((all ?? []).filter((c) => c.joined));
	const browse = $derived((all ?? []).filter((c) => !c.joined && c.is_public));

	function metricLabel(metricKey: ChallengeWithMeta['metric']): string {
		switch (metricKey) {
			case 'distance':
				return m('challenges.metricDistance');
			case 'duration':
				return m('challenges.metricDuration');
			case 'vert':
				return m('challenges.metricVert');
			case 'activity_count':
				return m('challenges.metricActivityCount');
			case 'streak_days':
				return m('challenges.metricStreak');
		}
	}
</script>

<svelte:head>
	<title>{m('challenges.title')}</title>
</svelte:head>

<div class="page">
	<header class="page-head">
		<p class="kicker">{m('challenges.kicker')}</p>
		<div class="head-row">
			<h1>{m('challenges.title')}</h1>
			<button type="button" class="btn btn-primary" onclick={() => (creating = true)}>
				{m('challenges.create')}
			</button>
		</div>
		<p class="tagline">{m('challenges.tagline')}</p>
	</header>

	{#if all === null}
		<p class="muted">…</p>
	{:else}
		<section>
			<h2>{m('challenges.myChallenges')}</h2>
			{#if mine.length === 0}
				<p class="muted">{m('challenges.empty')}</p>
			{:else}
				<ul class="list">
					{#each mine as c (c.id)}
						<li class="card-elevated">
							<a href={`/challenges/${c.id}`}>
								<div class="row-top">
									<span class="title">{c.title}</span>
									<span class="badge">{metricLabel(c.metric)}</span>
								</div>
								<ChallengeProgressBar metric={c.metric} value={c.my_value ?? 0} goal={c.goal_value} />
								<span class="meta">{m('challenges.participants', { n: c.participant_count })}</span>
							</a>
						</li>
					{/each}
				</ul>
			{/if}
		</section>

		<section>
			<h2>{m('challenges.browse')}</h2>
			{#if browse.length === 0}
				<p class="muted">{m('challenges.browseEmpty')}</p>
			{:else}
				<ul class="list">
					{#each browse as c (c.id)}
						<li class="card-elevated">
							<a href={`/challenges/${c.id}`}>
								<div class="row-top">
									<span class="title">{c.title}</span>
									<span class="badge">{metricLabel(c.metric)}</span>
								</div>
								<span class="meta">{m('challenges.participants', { n: c.participant_count })}</span>
							</a>
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}
</div>

<Modal open={creating} onclose={() => (creating = false)} title={m('challenges.create')}>
	<ChallengeEditor
		oncreated={(ch) => {
			creating = false;
			goto(`/challenges/${ch.id}`);
		}}
		oncancel={() => (creating = false)}
	/>
</Modal>

<style>
	.head-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
	}
	section {
		margin-top: var(--space-xl);
	}
	h2 {
		font-size: 1.1rem;
		margin: 0 0 var(--space-md);
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
		gap: var(--space-md);
	}
	.list li a {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-lg);
		text-decoration: none;
		color: inherit;
	}
	.row-top {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.title {
		font-weight: 600;
	}
	.badge {
		font-size: 0.75rem;
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		background: var(--color-surface-2, #f3f4f6);
		color: var(--color-text-muted, #6b7280);
	}
	.meta {
		font-size: 0.8rem;
		color: var(--color-text-muted, #6b7280);
	}
	.muted {
		color: var(--color-text-muted, #6b7280);
	}
</style>
