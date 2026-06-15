<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchSessionPlan,
		deleteSessionPlan,
		setSessionPlanPublic,
		publishSessionAsTemplate,
		fetchMyClubs,
		createGymWorkout,
		type SessionPlanWithItems
	} from '$lib/core/data';
	import type { ClubWithMeta } from '$lib/types';
	import {
		expandSessionSteps,
		type SessionPlanInput,
		type SessionStepResult,
		type SessionAdherence
	} from '$lib/social/session_steps';
	import { workoutDraftFromSession } from '$lib/social/event_gym_template';
	import { showToast } from '$lib/stores/toast.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import SessionPlanEditor from '$lib/components/SessionPlanEditor.svelte';
	import SessionRunner from '$lib/components/SessionRunner.svelte';
	import { goto } from '$app/navigation';
	import { smartBack } from '$lib/util/smart_back';
	import { m as t } from '$lib/i18n/store.svelte';

	let plan = $state<SessionPlanWithItems | null>(null);
	let loading = $state(true);
	let showEdit = $state(false);
	let confirmDelete = $state(false);
	let running = $state(false);
	let visibilityBusy = $state(false);
	let shareBusy = $state(false);
	let adminClubs = $state<ClubWithMeta[]>([]);
	let publishingTo = $state('');
	let publishBusy = $state(false);
	let failedFinish = $state<{ results: SessionStepResult[]; adherence: SessionAdherence } | null>(
		null
	);

	const back = smartBack();
	const planId = $derived($page.params.id ?? '');
	const isOwner = $derived(!!plan && !!auth.user && plan.author_id === auth.user.id);

	async function load() {
		plan = await fetchSessionPlan(planId);
		loading = false;
		// Only an owner of a personal (non-club) plan with at least one admin
		// club sees the publish-as-template control.
		if (plan && auth.user?.id && plan.author_id === auth.user.id && !plan.club_id) {
			const clubs = await fetchMyClubs();
			adminClubs = clubs.filter(
				(c) => c.viewer_role === 'owner' || c.viewer_role === 'admin'
			);
		}
	}

	async function publishToClub() {
		if (!plan || !publishingTo || publishBusy) return;
		publishBusy = true;
		try {
			await publishSessionAsTemplate(plan.id, publishingTo);
			showToast(t('session.publishSuccess'), 'success');
			publishingTo = '';
		} catch (e) {
			console.error('publish session template failed', e);
			showToast(t('session.publishFailed'), 'error');
		} finally {
			publishBusy = false;
		}
	}

	onMount(async () => {
		await auth.ready();
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

	let deleting = $state(false);
	async function doDelete() {
		if (deleting) return;
		deleting = true;
		try {
			await deleteSessionPlan(planId);
			confirmDelete = false;
			await goto('/sessions');
		} catch (e) {
			console.error('deleteSessionPlan failed', e);
			showToast(t('session.deleteFailed'), 'error');
		} finally {
			deleting = false;
		}
	}

	function onUpdated() {
		showEdit = false;
		load();
	}

	async function onSessionFinish(results: SessionStepResult[], adherence: SessionAdherence) {
		if (!plan) {
			running = false;
			return;
		}
		const draft = workoutDraftFromSession(expanded, plan.title, plan.discipline);
		try {
			await createGymWorkout({
				title: draft.title,
				duration_s: draft.duration_s,
				sets: draft.sets.map((s) => ({
					exercise_name: s.exercise_name,
					reps: s.reps,
					duration_s: s.duration_s
				})),
				metadata: {
					session_plan_id: plan.id,
					// snake_case wire shape — must match the Dart writer
					// (session_detail_screen._stepResultJson) + metadata.md.
					session_step_results: results.map((r) => ({
						item_id: r.itemId,
						movement_name: r.movementName,
						kind: r.kind,
						...(r.side ? { side: r.side } : {}),
						target_duration_s: r.targetDurationS,
						actual_duration_s: r.actualDurationS,
						status: r.status
					})),
					session_adherence: adherence.verdict
				}
			});
			failedFinish = null;
			showToast(t('session.run.saved'), 'success');
		} catch (e) {
			// Keep the finished session so the user can retry — never silently drop it.
			console.error('session run save failed', e);
			failedFinish = { results, adherence };
			showToast(t('session.run.saveFailed'), 'error');
		} finally {
			running = false;
		}
	}

	function retrySessionSave() {
		if (failedFinish) void onSessionFinish(failedFinish.results, failedFinish.adherence);
	}

	async function toggleVisibility() {
		if (!plan || visibilityBusy) return;
		const next = !plan.is_public;
		visibilityBusy = true;
		try {
			await setSessionPlanPublic(plan.id, next);
			plan = { ...plan, is_public: next };
		} catch (e) {
			console.error('toggle session visibility failed', e);
			showToast(t('session.visibilityError'), 'error');
		} finally {
			visibilityBusy = false;
		}
	}

	async function copyShareLink() {
		if (!plan || shareBusy) return;
		shareBusy = true;
		const url = `${location.origin}/share/session/${plan.id}`;
		try {
			// A non-public plan's share link 404s for everyone else, so make it
			// public first — mirrors the gym-workout share flow.
			if (!plan.is_public) {
				await setSessionPlanPublic(plan.id, true);
				plan = { ...plan, is_public: true };
			}
			await navigator.clipboard.writeText(url);
			showToast(t('session.shareLinkCopied'), 'success');
		} catch (e) {
			console.error('copy session share link failed', e);
			showToast(t('session.shareLinkError'), 'error');
		} finally {
			shareBusy = false;
		}
	}
</script>

<svelte:head><title>{plan?.title ?? t('session.title')}</title></svelte:head>

<div class="page">
	<a class="back" href="/sessions" onclick={back.handle}>&larr; {t('session.back')}</a>

	{#if loading}
		<p class="muted">…</p>
	{:else if !plan}
		<p data-testid="session-not-found">{t('session.notFound')}</p>
	{:else}
		{#if failedFinish}
			<div class="save-failed" role="alert" data-testid="session-save-failed">
				<span>{t('session.run.saveFailed')}</span>
				<button class="btn btn-sm" onclick={retrySessionSave} data-testid="session-retry-save">
					{t('session.run.retry')}
				</button>
			</div>
		{/if}
		<header class="detail-head">
			<div>
				<h1>{plan.title || t('session.untitled')}</h1>
				<p class="muted">
					{#if plan.discipline}{plan.discipline}{/if}
					{#if plan.equipment}· {plan.equipment}{/if}
					{#if expanded.totalS > 0}
						· {t('session.estDuration', { minutes: Math.round(expanded.totalS / 60) })}
					{/if}
					<span class="visibility-chip" class:is-public={plan.is_public}>
						{plan.is_public ? t('session.public') : t('session.private')}
					</span>
				</p>
			</div>
			<div class="head-actions">
				{#if expanded.steps.length > 0}
					<button
						type="button"
						class="btn btn-primary"
						onclick={() => (running = true)}
						data-testid="session-start"
					>
						{t('session.run.start')}
					</button>
				{/if}
				{#if isOwner}
					<button
						type="button"
						class="btn btn-secondary"
						onclick={toggleVisibility}
						disabled={visibilityBusy}
						data-testid="session-toggle-public"
					>
						{plan.is_public ? t('session.makePrivate') : t('session.makePublic')}
					</button>
					<button
						type="button"
						class="btn btn-secondary"
						onclick={copyShareLink}
						disabled={shareBusy}
						data-testid="session-copy-share-link"
					>
						{t('session.copyShareLink')}
					</button>
					<button type="button" class="btn btn-secondary" onclick={() => (showEdit = true)}>
						{t('session.save')}
					</button>
					<button type="button" class="btn btn-danger" onclick={() => (confirmDelete = true)}>
						{t('session.delete')}
					</button>
				{/if}
			</div>
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

		{#if isOwner && !plan.club_id && adminClubs.length > 0}
			<section class="publish-row">
				<span class="publish-label">{t('session.publishLabel')}</span>
				<select bind:value={publishingTo} aria-label={t('session.publishLabel')}>
					<option value="">{t('session.publishPick')}</option>
					{#each adminClubs as c (c.id)}
						<option value={c.id}>{c.name}</option>
					{/each}
				</select>
				<button
					type="button"
					class="btn btn-secondary"
					onclick={publishToClub}
					disabled={!publishingTo || publishBusy}
					data-testid="session-publish"
				>
					{t('session.publish')}
				</button>
			</section>
		{/if}
	{/if}
</div>

{#if plan && running}
	<SessionRunner
		{plan}
		steps={expanded.steps}
		onfinish={onSessionFinish}
		oncancel={() => (running = false)}
	/>
{/if}

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
	.save-failed {
		display: flex;
		align-items: center;
		gap: var(--space-md);
		justify-content: space-between;
		margin-bottom: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--danger);
		border-radius: var(--radius-md);
		color: var(--danger);
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
	.visibility-chip {
		display: inline-flex;
		align-items: center;
		font-size: 0.72rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--color-text-tertiary);
		background: var(--color-bg-secondary);
		padding: 0.1rem var(--space-sm);
		border-radius: var(--radius-sm);
	}
	.visibility-chip.is-public {
		color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.steps {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		padding-inline-start: var(--space-lg);
	}
	.steps li {
		display: flex;
		flex-direction: column;
	}
	.step-cue {
		color: var(--text-muted);
		font-size: 0.85rem;
	}
	.publish-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
		margin-top: var(--space-lg);
		padding-top: var(--space-md);
		border-top: 1px solid var(--border);
	}
	.publish-label {
		font-size: 0.9rem;
		color: var(--text-muted);
	}
</style>
