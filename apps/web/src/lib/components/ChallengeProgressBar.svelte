<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { formatDistance, formatElevation } from '$lib/format/units.svelte';
	import { formatDuration } from '$lib/format/time';
	import {
		progressFraction,
		isComplete,
		challengePace,
		type ChallengeMetric
	} from '$lib/social/challenge_progress';

	let {
		metric,
		value,
		goal,
		startsAt = null,
		endsAt = null
	}: {
		metric: ChallengeMetric;
		value: number;
		goal: number | null;
		startsAt?: string | null;
		endsAt?: string | null;
	} = $props();

	const fraction = $derived(progressFraction(value, goal));
	const complete = $derived(isComplete(value, goal));
	const pct = $derived(fraction === null ? 0 : Math.round(fraction * 100));

	const pace = $derived(
		goal !== null && startsAt && endsAt && !complete
			? challengePace(value, goal, new Date(startsAt).getTime(), new Date(endsAt).getTime(), Date.now())
			: null
	);
	const showPace = $derived(pace !== null && pace.status === 'active' && pace.verdict !== null);

	function fmt(v: number): string {
		switch (metric) {
			case 'distance':
				return formatDistance(v);
			case 'duration':
				return formatDuration(Math.round(v));
			case 'vert':
				return formatElevation(v);
			case 'streak_days':
				return m('challenges.unitDays', { n: Math.round(v) });
			case 'activity_count':
				return m('challenges.unitActivities', { n: Math.round(v) });
		}
	}
</script>

<div class="challenge-progress">
	<div class="label">
		{#if goal !== null}
			<span class="value">{m('challenges.goalProgress', { value: fmt(value), goal: fmt(goal) })}</span>
			{#if complete}
				<span class="complete">
					<span class="material-symbols" aria-hidden="true">check_circle</span>
					{m('challenges.progressComplete')}
				</span>
			{/if}
		{:else}
			<span class="value">{fmt(value)}</span>
		{/if}
	</div>
	{#if goal !== null}
		<div
			class="track"
			role="progressbar"
			aria-valuenow={pct}
			aria-valuemin="0"
			aria-valuemax="100"
		>
			<div class="fill" class:complete style="width: {pct}%"></div>
		</div>
	{/if}
	{#if showPace && pace}
		<div class="pace" class:behind={pace.verdict === 'behind'} class:ahead={pace.verdict === 'ahead'}>
			<span class="verdict">
				{#if pace.verdict === 'ahead'}
					{m('challenges.paceAhead')}
				{:else if pace.verdict === 'behind'}
					{m('challenges.paceBehind')}
				{:else}
					{m('challenges.paceOnTrack')}
				{/if}
			</span>
			{#if pace.verdict === 'behind' && pace.requiredPerDay !== null}
				<span class="need">{m('challenges.paceNeedPerDay', { rate: fmt(pace.requiredPerDay) })}</span>
			{/if}
		</div>
	{/if}
</div>

<style>
	.challenge-progress {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
	}
	.label {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-sm);
		font-size: 0.875rem;
	}
	.value {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
	.complete {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		color: var(--color-success);
		font-weight: 600;
	}
	.complete .material-symbols {
		width: 1.1em;
		height: 1.1em;
		font-size: 1.05em;
	}
	.track {
		height: 0.5rem;
		border-radius: 999px;
		background: var(--color-bg-tertiary);
		overflow: hidden;
	}
	.fill {
		height: 100%;
		background: linear-gradient(90deg, var(--color-primary), var(--color-secondary));
		border-radius: 999px;
		transition: width 0.4s ease;
	}
	.fill.complete {
		background: var(--color-success);
	}
	.pace {
		display: flex;
		align-items: baseline;
		gap: var(--space-sm);
		font-size: 0.8125rem;
		color: var(--color-text-secondary);
	}
	.pace .verdict {
		font-weight: 600;
		color: var(--color-primary);
	}
	.pace.ahead .verdict {
		color: var(--color-success);
	}
	.pace.behind .verdict {
		color: var(--color-warning);
	}
	.pace .need {
		font-variant-numeric: tabular-nums;
	}
	@media (prefers-reduced-motion: reduce) {
		.fill {
			transition: none;
		}
	}
</style>
