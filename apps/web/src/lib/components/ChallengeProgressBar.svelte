<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { formatDistance, formatElevation } from '$lib/format/units.svelte';
	import { formatDuration } from '$lib/format/time';
	import { progressFraction, isComplete, type ChallengeMetric } from '$lib/social/challenge_progress';

	let {
		metric,
		value,
		goal
	}: { metric: ChallengeMetric; value: number; goal: number | null } = $props();

	const fraction = $derived(progressFraction(value, goal));
	const complete = $derived(isComplete(value, goal));
	const pct = $derived(fraction === null ? 0 : Math.round(fraction * 100));

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
				<span class="complete">{m('challenges.progressComplete')}</span>
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
		color: var(--color-success, #16a34a);
		font-weight: 600;
	}
	.track {
		height: 0.5rem;
		border-radius: 999px;
		background: var(--color-border, #e5e7eb);
		overflow: hidden;
	}
	.fill {
		height: 100%;
		background: var(--color-accent, #2563eb);
		border-radius: 999px;
		transition: width 0.4s ease;
	}
	.fill.complete {
		background: var(--color-success, #16a34a);
	}
	@media (prefers-reduced-motion: reduce) {
		.fill {
			transition: none;
		}
	}
</style>
