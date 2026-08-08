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
	let loadError = $state<string | null>(null);
	let showCreate = $state(false);

	// fetchSessionPlans rethrows the Postgres error, and `loading` used to be
	// cleared only on the success path — so any failure left the page on its
	// spinner forever, with nothing said and nothing to retry.
	async function load() {
		loading = true;
		loadError = null;
		try {
			plans = await fetchSessionPlans();
		} catch (e) {
			loadError = e instanceof Error ? e.message : String(e);
		} finally {
			loading = false;
		}
	}

	onMount(async () => {
		await auth.ready();
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
		<div class="head-text">
			<a class="back-link" href="/gym">
				<span class="material-symbols" aria-hidden="true">arrow_back</span>
				{t('gym.back')}
			</a>
			<h1>{t('session.title')}</h1>
		</div>
		<button type="button" class="btn btn-primary" onclick={() => (showCreate = true)}>
			{t('session.new')}
		</button>
	</header>

	{#if loading}
		<p class="muted">…</p>
	{:else if loadError}
		<div class="error-banner" role="alert" data-testid="sessions-load-error">
			<span class="material-symbols" aria-hidden="true">error</span>
			<div>
				<strong>{t('session.loadError')}</strong>
				<span class="error-detail">{loadError}</span>
			</div>
			<button class="btn btn-outline" onclick={load}>{t('session.run.retry')}</button>
		</div>
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
		padding: var(--page-padding-y) var(--page-padding-x);
	}
	.page-head {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin-bottom: var(--space-lg);
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.muted {
		color: var(--color-text-tertiary);
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
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.error-banner {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		background: rgba(239, 68, 68, 0.08);
		border: 1px solid rgba(239, 68, 68, 0.3);
		border-radius: var(--radius-md);
		color: var(--color-text);
	}
	.error-banner > div {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
	}
	.error-detail {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
	}
</style>
