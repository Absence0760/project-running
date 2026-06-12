<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { fetchGymRoutineDetail, type GymRoutineDetail } from '$lib/core/data';
	import { expandRoutineSteps, type RoutineStep, type PlannedRoutine } from '$lib/gym/gym_routine';
	import GymSessionRunner from '$lib/components/GymSessionRunner.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	const routineId = $derived($page.params.routineId ?? '');

	let detail = $state<GymRoutineDetail | null>(null);
	let steps = $state<RoutineStep[]>([]);
	let loading = $state(true);

	async function load() {
		detail = await fetchGymRoutineDetail(routineId);
		if (detail) {
			const planned: PlannedRoutine = {
				title: detail.routine.title,
				exercises: detail.exercises.map((e) => ({
					exerciseName: e.exercise_name,
					position: e.position,
					supersetGroup: e.superset_group,
					supersetOrder: e.superset_order,
					sets: e.sets.map((s) => ({
						setIndex: s.set_index,
						setType: s.set_type,
						targetRepsMin: s.target_reps_min,
						targetRepsMax: s.target_reps_max,
						targetWeightKg: s.target_weight_kg,
						targetRpe: s.target_rpe,
						restS: s.rest_s,
						targetDurationS: s.target_duration_s,
					})),
				})),
			};
			steps = expandRoutineSteps(planned).steps;
		}
		loading = false;
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) return;
		await load();
	});

	function onfinish(workoutId: string) {
		goto(`/gym/${workoutId}`);
	}

	function oncancel() {
		goto(`/gym/routines/${routineId}`);
	}
</script>

<svelte:head>
	<title>{detail?.routine.title ?? t('gym.session.title')} — Threkir</title>
</svelte:head>

<div class="page">
	<a class="back-link" href={`/gym/routines/${routineId}`}>
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{t('gym.routine.back')}
	</a>

	{#if loading}
		<p class="sr-only" role="status">{t('shell.loading')}</p>
	{:else if !detail}
		<p class="not-found">{t('gym.routine.notFound')}</p>
	{:else if steps.length === 0}
		<p class="not-found">{t('gym.review.empty')}</p>
	{:else}
		<header class="session-head">
			<p class="head-eyebrow section-label">{t('gym.session.title')}</p>
			<h1>{detail.routine.title}</h1>
		</header>
		<GymSessionRunner routine={detail.routine} {steps} {onfinish} {oncancel} />
	{/if}
</div>

<style>
	.page {
		padding: var(--page-padding-y) var(--page-padding-x);
		max-width: 48rem;
	}
	.back-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		text-decoration: none;
	}
	.back-link:hover {
		color: var(--color-primary);
	}
	.session-head {
		margin: var(--space-sm) 0 var(--space-lg);
	}
	.head-eyebrow {
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	.session-head h1 {
		margin: 0;
	}
	.not-found {
		color: var(--color-text-secondary);
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
