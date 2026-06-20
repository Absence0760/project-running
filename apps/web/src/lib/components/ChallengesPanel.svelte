<script lang="ts">
	import { myActiveChallenges } from '$lib/core/data';
	import type { ChallengeWithMeta } from '$lib/types';
	import ChallengeProgressBar from './ChallengeProgressBar.svelte';
	import { m } from '$lib/i18n/store.svelte';

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
			<h2>{m('challenges.myChallenges')}</h2>
			<a href="/challenges" class="see-all">{m('challenges.browse')}</a>
		</header>
		<ul>
			{#each challenges as c (c.id)}
				<li>
					<a href={`/challenges/${c.id}`} class="mini">
						<span class="mini-title">{c.title}</span>
						<ChallengeProgressBar
							metric={c.metric}
							value={c.my_value ?? 0}
							goal={c.goal_value}
						/>
						{#if c.my_rank !== null}
							<span class="rank">{m('challenges.leaderboardRank', { rank: c.my_rank })}</span>
						{/if}
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
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	h2 {
		margin: 0;
		font-size: 1.1rem;
	}
	.see-all {
		font-size: 0.875rem;
		color: var(--color-accent, #2563eb);
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
		border-radius: var(--radius-md, 0.5rem);
		background: var(--color-surface-2, #f9fafb);
		text-decoration: none;
		color: inherit;
		position: relative;
	}
	.mini-title {
		font-weight: 600;
	}
	.rank {
		position: absolute;
		top: var(--space-sm);
		right: var(--space-md);
		font-size: 0.8rem;
		font-variant-numeric: tabular-nums;
		color: var(--color-text-muted, #6b7280);
	}
</style>
