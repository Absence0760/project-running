<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchSessionPlans, type SessionPlan } from '$lib/core/data';
	import Modal from '$lib/components/Modal.svelte';
	import SessionPlanEditor from '$lib/components/SessionPlanEditor.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	let plans = $state<SessionPlan[]>([]);
	let loading = $state(true);
	let showCreate = $state(false);

	async function load() {
		plans = await fetchSessionPlans();
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) {
			loading = false;
			return;
		}
		await load();
	});

	function onCreated(id: string) {
		showCreate = false;
		goto(`/sessions/${id}`);
	}
</script>

<svelte:head><title>{t('session.title')}</title></svelte:head>

<div class="page">
	<header class="page-head">
		<h1>{t('session.title')}</h1>
		<button type="button" class="btn btn-primary" onclick={() => (showCreate = true)}>
			{t('session.new')}
		</button>
	</header>

	{#if loading}
		<p class="muted">…</p>
	{:else if plans.length === 0}
		<div class="empty" data-testid="sessions-empty">
			<p>{t('session.empty')}</p>
			<p class="muted">{t('session.emptyHint')}</p>
		</div>
	{:else}
		<ul class="plan-list">
			{#each plans as plan (plan.id)}
				<li>
					<a class="card-elevated plan-row" href={`/sessions/${plan.id}`}>
						<span class="plan-title">{plan.title || t('session.untitled')}</span>
						<span class="plan-meta">
							{#if plan.discipline}{plan.discipline}{/if}
							{#if plan.est_duration_min}
								· {t('session.estDuration', { minutes: plan.est_duration_min })}
							{/if}
						</span>
					</a>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<Modal open={showCreate} title={t('session.new')} onclose={() => (showCreate = false)}>
	<SessionPlanEditor oncreated={onCreated} oncancel={() => (showCreate = false)} />
</Modal>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.page-head {
		display: flex;
		justify-content: space-between;
		align-items: center;
		margin-bottom: var(--space-lg);
	}
	.muted {
		color: var(--text-muted);
	}
	.empty {
		padding: var(--space-2xl);
		text-align: center;
	}
	.plan-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.plan-row {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		padding: var(--space-md);
		text-decoration: none;
		color: inherit;
	}
	.plan-title {
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.plan-meta {
		color: var(--text-muted);
		font-size: 0.9rem;
	}
</style>
