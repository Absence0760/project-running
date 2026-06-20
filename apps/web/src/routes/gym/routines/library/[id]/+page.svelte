<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import {
		fetchGymRoutineDetail,
		fetchPublicGymRoutineLibrary,
		cloneGymRoutineTemplate,
		type GymRoutineDetail,
	} from '$lib/core/data';
	import { formatWeight } from '$lib/format/units.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	const routineId = $derived($page.params.id ?? '');

	let detail = $state<GymRoutineDetail | null>(null);
	let authorHandle = $state<string | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let notFound = $state(false);
	let adopting = $state(false);

	async function load() {
		loading = true;
		loadError = null;
		notFound = false;
		const res = await fetchGymRoutineDetail(routineId);
		// fetchGymRoutineDetail honours RLS: a routine the viewer can't see
		// returns null. Confirm it's actually a public template so a viewer's
		// own private / club routine id can't masquerade as a library entry.
		if (!res || !res.routine.is_public_template) {
			notFound = true;
			loading = false;
			return;
		}
		detail = res;
		const lib = await fetchPublicGymRoutineLibrary('');
		authorHandle = lib.routines.find((r) => r.id === routineId)?.author_handle ?? null;
		loading = false;
	}

	async function adopt() {
		if (!detail || adopting) return;
		adopting = true;
		try {
			const newId = await cloneGymRoutineTemplate(detail.routine.id);
			showToast(t('gymLibrary.adoptSuccess'));
			goto(`/gym/routines/${newId}`);
		} catch (e) {
			console.error('adopt public gym routine failed', e);
			showToast(t('gymLibrary.adoptFailed'), 'error');
		} finally {
			adopting = false;
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
			return s.target_duration_s == null ? '—' : t('gym.durationValue', { seconds: s.target_duration_s });
		}
		if (modality === 'distance') {
			return s.target_distance_m == null ? '—' : `${s.target_distance_m} m`;
		}
		const reps = repLabel(s);
		if (modality === 'bodyweight_reps') return reps;
		const weight = s.target_weight_kg == null ? '—' : formatWeight(s.target_weight_kg);
		return `${reps} × ${weight}`;
	}

	onMount(load);
</script>

<svelte:head>
	<title>{detail ? detail.routine.title : t('gymLibrary.heading')}</title>
</svelte:head>

<div class="preview">
	<a class="back" href="/gym/routines/library">{t('gymLibrary.backToLibrary')}</a>

	{#if loading}
		<p class="state" role="status">{t('gymLibrary.loading')}</p>
	{:else if loadError}
		<div class="state error" role="alert">
			<p>{t('gymLibrary.loadError')}</p>
			<button class="btn btn-outline" type="button" onclick={load}>{t('gymLibrary.retry')}</button>
		</div>
	{:else if notFound || !detail}
		<p class="state" data-testid="gym-library-not-found">{t('gymLibrary.notFound')}</p>
	{:else}
		<header class="preview-head">
			<h1>{detail.routine.title}</h1>
			<p class="author">
				{t('gymLibrary.byAuthor', {
					author: authorHandle ?? t('gymLibrary.anonymousAuthor'),
				})}
			</p>
			<div class="chips">
				<span class="chip">{t('gymLibrary.exercisesLabel', { count: detail.routine.exercise_count })}</span>
			</div>
			{#if detail.routine.notes}
				<p class="notes">{detail.routine.notes}</p>
			{/if}
		</header>

		<section class="adopt-row">
			<button
				class="btn btn-primary"
				type="button"
				disabled={adopting}
				onclick={adopt}
				data-testid="gym-library-adopt"
			>
				{adopting ? t('gymLibrary.adopting') : t('gymLibrary.adopt')}
			</button>
		</section>

		<section class="exercises">
			<h2>{t('gymLibrary.previewExercises')}</h2>
			<ul class="exercise-list">
				{#each detail.exercises as ex (ex.id)}
					<li class="exercise-card">
						<span class="exercise-name">{ex.exercise_name}</span>
						<table class="set-table">
							<tbody>
								{#each ex.sets as s (s.set_index)}
									<tr>
										<td>{t(`gym.routine.setType.${s.set_type}`)}</td>
										<td>{targetLabel(ex.modality, s)}</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</li>
				{/each}
			</ul>
		</section>
	{/if}
</div>

<style>
	.preview {
		max-width: 720px;
		margin: 0 auto;
		padding: 1rem;
	}
	.back {
		font-size: 0.85rem;
		color: var(--text-muted, #667);
		text-decoration: none;
	}
	.state {
		text-align: center;
		color: var(--text-muted, #667);
		padding: 2rem 0;
	}
	.state.error {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
		align-items: center;
	}
	.preview-head h1 {
		margin: 0.5rem 0 0.25rem;
		font-size: 1.5rem;
	}
	.author {
		margin: 0 0 0.5rem;
		color: var(--text-muted, #667);
	}
	.chips {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
	}
	.chip {
		font-size: 0.75rem;
		padding: 0.15rem 0.5rem;
		border-radius: 1rem;
		background: var(--chip-bg, #eef);
		color: var(--chip-fg, #335);
	}
	.notes {
		margin: 0.5rem 0 0;
	}
	.adopt-row {
		display: flex;
		gap: 0.75rem;
		margin: 1.25rem 0;
		flex-wrap: wrap;
	}
	.exercise-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.exercise-card {
		padding: 0.75rem;
		border: 1px solid var(--border, #ccd);
		border-radius: 0.5rem;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.exercise-name {
		font-weight: 600;
	}
	.set-table {
		border-collapse: collapse;
		width: 100%;
		max-width: 24rem;
	}
	.set-table td {
		padding-inline-end: 1rem;
	}
</style>
