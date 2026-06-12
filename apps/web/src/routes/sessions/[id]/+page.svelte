<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchSessionPlan,
		deleteSessionPlan,
		type SessionPlanWithItems
	} from '$lib/core/data';
	import { expandSessionSteps, type SessionPlanInput } from '$lib/social/session_steps';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import SessionPlanEditor from '$lib/components/SessionPlanEditor.svelte';
	import { goto } from '$app/navigation';
	import { m as t } from '$lib/i18n/store.svelte';

	let plan = $state<SessionPlanWithItems | null>(null);
	let loading = $state(true);
	let showEdit = $state(false);
	let confirmDelete = $state(false);

	const planId = $derived($page.params.id ?? '');
	const isOwner = $derived(!!plan && !!auth.user && plan.author_id === auth.user.id);

	async function load() {
		plan = await fetchSessionPlan(planId);
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		await load();
	});

	const expanded = $derived.by(() => {
		if (!plan) return { steps: [], totalS: 0 };
		const input: SessionPlanInput = {
			blocks: plan.blocks.map((b) => ({ id: b.id, position: b.position, name: b.name })),
			items: plan.items.map((it) => ({
				id: it.id,
				block_id: it.block_id,
				position: it.position,
				movement_name: it.movement_name,
				kind: it.kind,
				duration_s: it.duration_s,
				reps: it.reps,
				per_side: it.per_side,
				tempo: it.tempo,
				cue: it.cue
			}))
		};
		return expandSessionSteps(input);
	});

	function stepName(step: (typeof expanded.steps)[number]): string {
		if (step.side === 'left') return t('session.sideLeft', { name: step.movementName });
		if (step.side === 'right') return t('session.sideRight', { name: step.movementName });
		return step.movementName;
	}

	function stepLabel(step: (typeof expanded.steps)[number]): string {
		const name = stepName(step);
		if (step.kind === 'reps') {
			return t('session.stepReps', { name, reps: step.reps ?? 0 });
		}
		if (step.kind === 'flow') {
			return t('session.stepFlow', { name, seconds: step.durationS ?? 0 });
		}
		return t('session.stepHold', { name, seconds: step.durationS ?? 0 });
	}

	async function doDelete() {
		await deleteSessionPlan(planId);
		confirmDelete = false;
		goto('/sessions');
	}

	function onUpdated() {
		showEdit = false;
		load();
	}
</script>

<svelte:head><title>{plan?.title ?? t('session.title')}</title></svelte:head>

<div class="page">
	<a class="back" href="/sessions">&larr; {t('session.back')}</a>

	{#if loading}
		<p class="muted">…</p>
	{:else if !plan}
		<p data-testid="session-not-found">{t('session.notFound')}</p>
	{:else}
		<header class="detail-head">
			<div>
				<h1>{plan.title || t('session.untitled')}</h1>
				<p class="muted">
					{#if plan.discipline}{plan.discipline}{/if}
					{#if plan.equipment}· {plan.equipment}{/if}
					{#if expanded.totalS > 0}
						· {t('session.estDuration', { minutes: Math.round(expanded.totalS / 60) })}
					{/if}
				</p>
			</div>
			{#if isOwner}
				<div class="head-actions">
					<button type="button" class="btn btn-secondary" onclick={() => (showEdit = true)}>
						{t('session.save')}
					</button>
					<button type="button" class="btn btn-danger" onclick={() => (confirmDelete = true)}>
						{t('session.delete')}
					</button>
				</div>
			{/if}
		</header>

		<section>
			<h2>{t('session.steps')}</h2>
			<ol class="steps" data-testid="session-steps">
				{#each expanded.steps as step (step.itemId + (step.side ?? ''))}
					<li>
						<span class="step-label">{stepLabel(step)}</span>
						{#if step.cue}<span class="step-cue">{step.cue}</span>{/if}
					</li>
				{/each}
			</ol>
		</section>
	{/if}
</div>

{#if plan}
	<Modal open={showEdit} title={t('session.save')} onclose={() => (showEdit = false)}>
		<SessionPlanEditor existing={plan} onupdated={onUpdated} oncancel={() => (showEdit = false)} />
	</Modal>
{/if}

<ConfirmDialog
	open={confirmDelete}
	title={t('session.delete')}
	message={t('session.deleteConfirm')}
	confirmLabel={t('session.delete')}
	onconfirm={doDelete}
	oncancel={() => (confirmDelete = false)}
/>

<style>
	.page {
		padding: var(--space-xl) var(--space-2xl);
	}
	.back {
		display: inline-block;
		margin-bottom: var(--space-md);
		color: var(--text-muted);
		text-decoration: none;
	}
	.detail-head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin-bottom: var(--space-lg);
	}
	.head-actions {
		display: flex;
		gap: var(--space-sm);
	}
	.muted {
		color: var(--text-muted);
	}
	.steps {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		padding-left: var(--space-lg);
	}
	.steps li {
		display: flex;
		flex-direction: column;
	}
	.step-cue {
		color: var(--text-muted);
		font-size: 0.85rem;
	}
</style>
