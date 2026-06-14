<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { formatISO } from '$lib/training/training';
	import {
		fetchPlan,
		fetchPublicPlanLibrary,
		clonePublicPlan,
	} from '$lib/core/data';
	import { formatDistance } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import type { TrainingPlan, PlanWeek, PlanWorkout } from '$lib/types';

	const planId = $page.params.id ?? '';

	let plan = $state<TrainingPlan | null>(null);
	let weeks = $state<PlanWeek[]>([]);
	let workouts = $state<PlanWorkout[]>([]);
	let authorHandle = $state<string | null>(null);
	let loading = $state(true);
	let loadError = $state<string | null>(null);
	let notFound = $state(false);
	let cloning = $state(false);
	let startDate = $state(defaultStartDate());

	function defaultStartDate(): string {
		const d = new Date();
		const offset = (8 - d.getDay()) % 7;
		d.setDate(d.getDate() + (offset === 0 ? 7 : offset));
		return formatISO(d);
	}

	const eventLabels: Record<string, () => string> = {
		distance_5k: () => '5K',
		distance_10k: () => '10K',
		distance_half: () => m('plansPage.eventHalf'),
		distance_full: () => m('plansPage.eventFull'),
		custom: () => m('plansPage.eventCustom'),
	};

	function goalLabel(p: TrainingPlan): string {
		const named = eventLabels[p.goal_event];
		return named ? named() : formatDistance(p.goal_distance_m);
	}

	const workoutsByWeek = $derived.by(() => {
		const map = new Map<string, PlanWorkout[]>();
		for (const w of workouts) {
			const list = map.get(w.week_id) ?? [];
			list.push(w);
			map.set(w.week_id, list);
		}
		return map;
	});

	async function load() {
		loading = true;
		loadError = null;
		notFound = false;
		const res = await fetchPlan(planId);
		if (res.error) {
			loadError = res.error;
			loading = false;
			return;
		}
		// fetchPlan honours RLS: a non-public plan the viewer doesn't own
		// returns null. The dedicated public-library entry also confirms
		// the row is actually published (a viewer's own private plan id
		// could otherwise sneak through fetchPlan).
		if (!res.plan || !res.plan.is_public_template) {
			notFound = true;
			loading = false;
			return;
		}
		plan = res.plan;
		weeks = res.weeks;
		workouts = res.workouts;
		const lib = await fetchPublicPlanLibrary('');
		authorHandle = lib.plans.find((p) => p.id === planId)?.author_handle ?? null;
		loading = false;
	}

	async function clone() {
		if (!plan || cloning) return;
		cloning = true;
		try {
			const newId = await clonePublicPlan(plan.id, startDate);
			showToast(m('planLibrary.cloneSuccess'));
			goto(`/plans/${newId}`);
		} catch (e) {
			showToast(m('planLibrary.cloneFailed', { error: String(e) }), 'error');
		} finally {
			cloning = false;
		}
	}

	onMount(load);
</script>

<svelte:head>
	<title>{plan ? plan.name : m('planLibrary.heading')}</title>
</svelte:head>

<div class="preview">
	<a class="back" href="/plans/library">{m('planLibrary.backToLibrary')}</a>

	{#if loading}
		<p class="state">{m('planLibrary.loading')}</p>
	{:else if loadError}
		<div class="state error">
			<p>{m('planLibrary.loadError')}</p>
			<button class="btn btn-outline" type="button" onclick={load}>
				{m('planLibrary.retry')}
			</button>
		</div>
	{:else if notFound || !plan}
		<p class="state">{m('planLibrary.notFound')}</p>
	{:else}
		<header class="preview-head">
			<h1>{plan.name}</h1>
			<p class="author">
				{m('planLibrary.byAuthor', {
					author: authorHandle ?? m('planLibrary.anonymousAuthor'),
				})}
			</p>
			<div class="chips">
				<span class="chip">{goalLabel(plan)}</span>
				<span class="chip">{m('planLibrary.weeksLabel', { weeks: weeks.length })}</span>
				<span class="chip">{m('planLibrary.daysPerWeek', { days: plan.days_per_week })}</span>
			</div>
		</header>

		<section class="clone-row">
			<label class="start">
				<span>{m('planLibrary.startDateLabel')}</span>
				<input type="date" bind:value={startDate} />
			</label>
			<button class="btn btn-primary" type="button" disabled={cloning} onclick={clone}>
				{cloning ? m('planLibrary.cloning') : m('planLibrary.clone')}
			</button>
		</section>

		<section class="weeks">
			<h2>{m('planLibrary.previewWeeks')}</h2>
			<ol>
				{#each weeks as w (w.id)}
					<li>
						<span class="week-label">{m('planLibrary.previewWeek', { n: w.week_index + 1 })}</span>
						<span class="week-count">
							{(workoutsByWeek.get(w.id) ?? []).length}
						</span>
					</li>
				{/each}
			</ol>
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
	.clone-row {
		display: flex;
		align-items: flex-end;
		gap: 0.75rem;
		margin: 1.25rem 0;
		flex-wrap: wrap;
	}
	.start {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		font-size: 0.85rem;
	}
	.start input {
		padding: 0.5rem;
		border: 1px solid var(--border, #ccd);
		border-radius: 0.5rem;
	}
	.weeks ol {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.weeks li {
		display: flex;
		justify-content: space-between;
		padding: 0.6rem 0.75rem;
		border: 1px solid var(--border, #ccd);
		border-radius: 0.5rem;
	}
	.week-count {
		color: var(--text-muted, #667);
		font-variant-numeric: tabular-nums;
	}
</style>
