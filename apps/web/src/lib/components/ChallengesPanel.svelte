<script lang="ts">
	import { myActiveChallenges } from '$lib/core/data';
	import type { ChallengeWithMeta, ChallengeMetric } from '$lib/types';
	import ChallengeProgressBar from './ChallengeProgressBar.svelte';
	import { m } from '$lib/i18n/store.svelte';

	const METRIC_ICON: Record<ChallengeMetric, string> = {
		distance: 'straighten',
		duration: 'timer',
		vert: 'terrain',
		activity_count: 'format_list_numbered',
		streak_days: 'local_fire_department'
	};
	function metricLabel(metric: ChallengeMetric): string {
		switch (metric) {
			case 'distance':
				return m('challenges.metricDistance');
			case 'duration':
				return m('challenges.metricDuration');
			case 'vert':
				return m('challenges.metricVert');
			case 'activity_count':
				return m('challenges.metricActivityCount');
			case 'streak_days':
				return m('challenges.metricStreak');
		}
	}

	// Self-hiding entry point: renders nothing when the caller is in no live
	// challenge, so non-joiners never see clutter. Mounted on /dashboard + the
	// /social Challenges tab.
	let challenges = $state<ChallengeWithMeta[] | null>(null);

	$effect(() => {
		myActiveChallenges()
			.then((rows) => {
				challenges = rows;
			})
			.catch(() => {
				challenges = [];
			});
	});
</script>

{#if challenges && challenges.length > 0}
	<section class="challenges-strip card-elevated" aria-label={m('challenges.myChallenges')}>
		<header>
			<span class="head-ident">
				<span class="material-symbols head-icon" aria-hidden="true">trophy</span>
				<h2>{m('challenges.myChallenges')}</h2>
			</span>
			<a href="/challenges" class="see-all">
				{m('challenges.browse')}
				<span class="material-symbols" aria-hidden="true">chevron_right</span>
			</a>
		</header>
		<ul>
			{#each challenges as c (c.id)}
				<li>
					<a href={`/challenges/${c.id}`} class="mini">
						<div class="mini-top">
							<span class="mini-title">{c.title}</span>
							{#if c.my_rank !== null}
								<span class="rank">{m('challenges.leaderboardRank', { rank: c.my_rank })}</span>
							{/if}
						</div>
						<span class="metric-chip">
							<span class="material-symbols" aria-hidden="true">{METRIC_ICON[c.metric]}</span>
							{metricLabel(c.metric)}
						</span>
						<ChallengeProgressBar
							metric={c.metric}
							value={c.my_value ?? 0}
							goal={c.goal_value}
						/>
					</a>
				</li>
			{/each}
		</ul>
	</section>
{/if}

<style>
	.challenges-strip {
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.head-ident {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.head-icon {
		color: var(--color-secondary);
		font-size: 1.3rem;
	}
	h2 {
		margin: 0;
		font-size: 1.1rem;
	}
	.see-all {
		display: inline-flex;
		align-items: center;
		gap: 0.1rem;
		font-size: 0.875rem;
		font-weight: 600;
		color: var(--color-primary);
		text-decoration: none;
	}
	.see-all .material-symbols {
		font-size: 1.1rem;
	}
	.see-all:hover {
		text-decoration: underline;
	}
	ul {
		list-style: none;
		margin: 0;
		padding: 0;
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr));
		gap: var(--space-md);
	}
	.mini {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		padding: var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		text-decoration: none;
		color: inherit;
		transition:
			transform 0.15s ease,
			border-color 0.15s ease,
			box-shadow 0.15s ease;
	}
	.mini:hover {
		transform: translateY(-2px);
		border-color: color-mix(in srgb, var(--color-primary) 40%, var(--color-border));
		box-shadow: var(--shadow-sm);
	}
	.mini-top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.mini-title {
		font-weight: 600;
		line-height: 1.3;
	}
	.rank {
		flex-shrink: 0;
		padding: 0.05rem 0.45rem;
		border-radius: 999px;
		background: var(--color-primary-light);
		color: var(--color-primary);
		font-size: 0.78rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.metric-chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		align-self: flex-start;
		font-size: 0.78rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}
	.metric-chip .material-symbols {
		font-size: 1rem;
		width: 1rem;
		height: 1rem;
		color: var(--color-text-tertiary);
	}
</style>
