<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { formatDistance, formatElevation } from '$lib/format/units.svelte';
	import { formatDuration } from '$lib/format/time';
	import type { ChallengeLeaderboardRow, ChallengeMetric, ChallengeScope } from '$lib/types';

	let {
		rows,
		metric,
		scope,
		clubNames = {},
		meId = null
	}: {
		rows: ChallengeLeaderboardRow[];
		metric: ChallengeMetric;
		scope: ChallengeScope;
		clubNames?: Record<string, string>;
		meId?: string | null;
	} = $props();

	const byTeam = $derived(scope === 'club_vs_club');

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

	function nameFor(row: ChallengeLeaderboardRow): string {
		if (byTeam) return clubNames[row.team_club_id ?? ''] ?? row.team_club_id ?? '—';
		return row.display_name ?? m('checkpoint.anonymousRunner');
	}
</script>

{#if rows.length === 0}
	<p class="empty">{m('challenges.leaderboardEmpty')}</p>
{:else}
	<ol class="board" aria-label={m('challenges.leaderboard')}>
		{#each rows as row (byTeam ? row.team_club_id : row.user_id)}
			<li class="row" class:me={!byTeam && meId && row.user_id === meId}>
				<span class="rank" class:medal={row.rank <= 3} data-rank={row.rank}>
					{m('challenges.leaderboardRank', { rank: row.rank })}
				</span>
				<span class="name">{nameFor(row)}</span>
				<span class="val">{fmt(row.value)}</span>
			</li>
		{/each}
	</ol>
{/if}

<style>
	.board {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs, 0.25rem);
	}
	.row {
		display: grid;
		grid-template-columns: 2.75rem 1fr auto;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-bg-secondary);
		border: 1px solid transparent;
	}
	.row.me {
		background: var(--color-primary-light);
		border-color: color-mix(in srgb, var(--color-primary) 30%, transparent);
		font-weight: 600;
	}
	.rank {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 2.25rem;
		padding: 0.1rem 0.4rem;
		border-radius: 999px;
		font-variant-numeric: tabular-nums;
		color: var(--color-text-secondary);
		font-weight: 700;
		font-size: 0.85rem;
	}
	.rank.medal {
		color: #3a2e0a;
	}
	.rank.medal[data-rank='1'] {
		background: linear-gradient(135deg, #f6d671, #d4a017);
	}
	.rank.medal[data-rank='2'] {
		background: linear-gradient(135deg, #e4e7eb, #b4bcc4);
	}
	.rank.medal[data-rank='3'] {
		background: linear-gradient(135deg, #e6b27e, #c08043);
	}
	.name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.val {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
	.empty {
		color: var(--color-text-secondary);
		font-size: 0.875rem;
	}
</style>
