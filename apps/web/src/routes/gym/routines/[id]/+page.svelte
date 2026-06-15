<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { smartBack } from '$lib/util/smart_back';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchGymRoutineDetail,
		deleteGymRoutine,
		fetchMyClubs,
		publishGymRoutineAsTemplate,
		type GymRoutineDetail,
	} from '$lib/core/data';
	import type { ClubWithMeta } from '$lib/types';
	import { formatWeight } from '$lib/format/units.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	let detail = $state<GymRoutineDetail | null>(null);
	let loading = $state(true);
	let confirmingDelete = $state(false);
	let adminClubs = $state<ClubWithMeta[]>([]);
	let publishingTo = $state('');
	let publishBusy = $state(false);

	const back = smartBack();
	const routineId = $derived($page.params.id ?? '');
	const isOwner = $derived(!!detail && !!auth.user && detail.routine.author_id === auth.user.id);

	async function load() {
		detail = await fetchGymRoutineDetail(routineId);
		loading = false;
		// Only the author of a personal (non-club) routine with at least one
		// admin club sees the publish-as-template control.
		if (detail && auth.user?.id && detail.routine.author_id === auth.user.id && !detail.routine.club_id) {
			const clubs = await fetchMyClubs();
			adminClubs = clubs.filter((c) => c.viewer_role === 'owner' || c.viewer_role === 'admin');
		}
	}

	async function publishToClub() {
		if (!detail || !publishingTo || publishBusy) return;
		publishBusy = true;
		try {
			await publishGymRoutineAsTemplate(detail.routine.id, publishingTo);
			showToast(t('gym.routine.publishSuccess'), 'success');
			publishingTo = '';
		} catch (e) {
			console.error('publish gym routine template failed', e);
			showToast(t('gym.routine.publishFailed'), 'error');
		} finally {
			publishBusy = false;
		}
	}

	onMount(async () => {
		await auth.ready();
		if (!auth.user) return;
		await load();
	});

	async function doDelete() {
		try {
			await deleteGymRoutine(routineId);
			showToast(t('gym.routine.deleted'));
			goto('/gym/routines');
		} catch (e) {
			console.error('routine delete failed', e);
			showToast(t('gym.routine.saveFailed'));
		}
	}

	function repLabel(s: { target_reps_min: number | null; target_reps_max: number | null }): string {
		if (s.target_reps_min == null) return '—';
		if (s.target_reps_max != null && s.target_reps_max !== s.target_reps_min) {
			return `${s.target_reps_min}–${s.target_reps_max}`;
		}
		return String(s.target_reps_min);
	}

	function targetLabel(
		modality: string,
		s: {
			target_reps_min: number | null;
			target_reps_max: number | null;
			target_weight_kg: number | null;
			target_duration_s: number | null;
			target_distance_m: number | null;
		},
	): string {
		if (modality === 'time') {
			return s.target_duration_s == null
				? '—'
				: t('gym.durationValue', { seconds: s.target_duration_s });
		}
		if (modality === 'distance') {
			return s.target_distance_m == null ? '—' : `${s.target_distance_m} m`;
		}
		const reps = repLabel(s);
		if (modality === 'bodyweight_reps') return reps;
		const weight = s.target_weight_kg == null ? '—' : formatWeight(s.target_weight_kg);
		return `${reps} × ${weight}`;
	}
</script>

<svelte:head><title>{detail?.routine.title ?? t('gym.routine.title')} — Threkir</title></svelte:head>

<div class="page">
	<a class="back-link" href="/gym/routines" onclick={back.handle}>
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{t('gym.routine.back')}
	</a>

	{#if loading}
		<p class="sr-only" role="status">{t('shell.loading')}</p>
	{:else if !detail}
		<p class="not-found">{t('gym.routine.notFound')}</p>
	{:else}
		<header class="detail-header">
			<div>
				<h1>{detail.routine.title}</h1>
				<p class="head-sub">
					{t('gym.routine.exerciseCount', { count: detail.routine.exercise_count })}
				</p>
				{#if detail.routine.notes}
					<p class="notes">{detail.routine.notes}</p>
				{/if}
			</div>
			<div class="head-actions">
				<button
					class="btn btn-primary"
					onclick={() => goto(`/gym/session/${routineId}`)}
					data-testid="routine-start"
				>
					<span class="material-symbols" aria-hidden="true">play_arrow</span>
					{t('gym.routine.start')}
				</button>
				<button
					class="btn btn-danger"
					onclick={() => (confirmingDelete = true)}
					data-testid="routine-delete"
				>
					{t('gym.routine.delete')}
				</button>
			</div>
		</header>

		{#if detail.routine.club_id}
			<p class="club-template-badge" data-testid="routine-club-template">
				<span class="material-symbols" aria-hidden="true">groups</span>
				{t('gym.routine.clubTemplateBadge')}
			</p>
		{:else if isOwner && adminClubs.length > 0}
			<section class="publish-row">
				<span class="publish-label">{t('gym.routine.publishLabel')}</span>
				<select bind:value={publishingTo} aria-label={t('gym.routine.publishLabel')}>
					<option value="">{t('gym.routine.publishPick')}</option>
					{#each adminClubs as c (c.id)}
						<option value={c.id}>{c.name}</option>
					{/each}
				</select>
				<button
					type="button"
					class="btn btn-secondary"
					onclick={publishToClub}
					disabled={!publishingTo || publishBusy}
					data-testid="routine-publish"
				>
					{t('gym.routine.publish')}
				</button>
			</section>
		{/if}

		<ul class="exercise-list" data-testid="routine-exercises">
			{#each detail.exercises as ex (ex.id)}
				<li class="card-elevated exercise-card" class:supersetted={ex.superset_group != null}>
					<div class="exercise-head">
						<span class="exercise-name">{ex.exercise_name}</span>
						{#if ex.superset_group != null}
							<span class="chip chip-superset" data-testid="routine-superset-badge">
								<span class="material-symbols" aria-hidden="true">repeat</span>
								{t('gym.routine.supersetBadge', { group: ex.superset_group })}
							</span>
						{/if}
						{#if ex.progression !== 'none'}
							<span class="chip chip-progression">
								<span class="material-symbols" aria-hidden="true">trending_up</span>
								{t(`gym.routine.progression.${ex.progression}`)}
							</span>
						{/if}
					</div>
					<table class="set-table">
						<thead>
							<tr>
								<th class="section-label">{t('gym.routine.setType')}</th>
								<th class="section-label">{t('gym.routine.targetReps')}</th>
								<th class="section-label">{t('gym.routine.restLabel')}</th>
							</tr>
						</thead>
						<tbody>
							{#each ex.sets as s (s.set_index)}
								<tr>
									<td>{t(`gym.routine.setType.${s.set_type}`)}</td>
									<td>{targetLabel(ex.modality, s)}</td>
									<td>{s.rest_s == null ? '—' : t('gym.durationValue', { seconds: s.rest_s })}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<ConfirmDialog
	open={confirmingDelete}
	title={t('gym.routine.deleteConfirm.title')}
	message={t('gym.routine.deleteConfirm.body')}
	confirmLabel={t('gym.routine.delete')}
	danger
	onconfirm={doDelete}
	oncancel={() => (confirmingDelete = false)}
/>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--text-muted);
		font-size: 0.9rem;
	}
	.detail-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		margin: var(--space-sm) 0 var(--space-lg);
	}
	.head-sub {
		color: var(--text-muted);
		margin: var(--space-2xs) 0 0;
	}
	.notes {
		margin: var(--space-2xs) 0 0;
	}
	.head-actions {
		display: flex;
		gap: var(--space-sm);
	}
	.publish-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
		margin: 0 0 var(--space-lg);
	}
	.publish-label {
		color: var(--text-muted);
		font-size: 0.9rem;
	}
	.club-template-badge {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-primary);
		font-size: 0.9rem;
		margin: 0 0 var(--space-lg);
	}
	.club-template-badge .material-symbols {
		font-size: 1.1rem;
	}
	.exercise-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.exercise-card {
		padding: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.exercise-card.supersetted {
		border-inline-start: 3px solid var(--color-primary);
	}
	.exercise-head {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.exercise-name {
		font-weight: 600;
	}
	.chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.7rem;
		font-weight: 700;
		letter-spacing: 0.03em;
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
	}
	.chip .material-symbols {
		font-size: 0.85rem;
	}
	.chip-superset {
		color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.chip-progression {
		color: var(--color-text-secondary);
		background: var(--color-bg-secondary);
	}
	.set-table {
		border-collapse: collapse;
		width: 100%;
		max-width: 24rem;
	}
	.set-table th {
		text-align: start;
		padding-inline-end: var(--space-md);
	}
	.set-table td {
		padding-inline-end: var(--space-md);
	}
	.not-found {
		color: var(--text-muted);
	}
</style>
