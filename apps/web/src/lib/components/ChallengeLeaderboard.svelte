<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { formatDistance, formatElevation } from '$lib/format/units.svelte';
	import { formatDuration } from '$lib/format/time';
	import type { ChallengeLeaderboardRow, ChallengeMetric, ChallengeScope } from '$lib/types';
	import { teamLabel } from '$lib/social/challenge_list';
	import { standingFor } from '$lib/social/leaderboard_standing';

	let {
		rows,
		metric,
		scope,
		clubNames = {},
		meId = null,
		meTeamId = null
	}: {
		rows: ChallengeLeaderboardRow[];
		metric: ChallengeMetric;
		scope: ChallengeScope;
		clubNames?: Record<string, string>;
		meId?: string | null;
		meTeamId?: string | null;
	} = $props();

	const byTeam = $derived(scope === 'club_vs_club');
	const standing = $derived(standingFor(rows, byTeam ? meTeamId : meId));

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
		if (!byTeam) return row.display_name ?? m('checkpoint.anonymousRunner');
		const label = teamLabel(row.team_club_id, clubNames);
		if (label.kind === 'named') return label.name;
		return label.kind === 'no_club' ? m('challenges.teamNoClub') : m('challenges.teamPrivateClub');
	}
</script>

{#if rows.length === 0}
	<p class="empty">{m('challenges.leaderboardEmpty')}</p>
{:else}
	{#if standing && rows.length > 1}
		<div class="standing" data-testid="challenge-standing">
			<span class="standing-label"
				>{byTeam ? m('challenges.standingTitleTeam') : m('challenges.standingTitle')}</span
			>
			<span class="standing-rank"
				>{m('challenges.standingRank', { rank: standing.rank, total: standing.total })}</span
			>
			{#if standing.tiedWith > 0}
				<span class="standing-gap">
					{standing.tiedWith === 1
						? m('challenges.standingTiedOne')
						: m('challenges.standingTiedMany', { n: standing.tiedWith })}
				</span>
			{/if}
			{#if standing.chasing}
				<span class="standing-gap">
					{m('challenges.standingBehind', {
						gap: fmt(standing.chasing.delta),
						name: nameFor(standing.chasing.entry)
					})}
				</span>
			{:else}
				<span class="standing-gap leading">{m('challenges.standingLeading')}</span>
			{/if}
			{#if standing.chasedBy}
				<span class="standing-gap">
					{m('challenges.standingAhead', {
						gap: fmt(standing.chasedBy.delta),
						name: nameFor(standing.chasedBy.entry)
					})}
				</span>
			{/if}
		</div>
	{/if}
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
	.standing {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: var(--space-2xs, 0.25rem) var(--space-sm);
		margin-bottom: var(--space-md);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md);
		background: var(--color-primary-light);
		border: 1px solid color-mix(in srgb, var(--color-primary) 30%, transparent);
		font-size: 0.875rem;
	}
	.standing-label {
		font-weight: 700;
		color: var(--color-text);
	}
	.standing-rank {
		font-variant-numeric: tabular-nums;
		font-weight: 700;
		color: var(--color-primary);
	}
	.standing-gap {
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.standing-gap.leading {
		color: var(--color-success-text);
		font-weight: 600;
	}
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
