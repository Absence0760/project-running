<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { formatDistance } from '$lib/format/units.svelte';
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
				<span class="rank">{m('challenges.leaderboardRank', { rank: row.rank })}</span>
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
		grid-template-columns: 2.5rem 1fr auto;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-sm) var(--space-md);
		border-radius: var(--radius-md, 0.5rem);
		background: var(--color-surface-2, #f9fafb);
	}
	.row.me {
		background: var(--color-accent-soft, #eff6ff);
		font-weight: 600;
	}
	.rank {
		font-variant-numeric: tabular-nums;
		color: var(--color-text-muted, #6b7280);
		font-weight: 600;
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
		color: var(--color-text-muted, #6b7280);
		font-size: 0.875rem;
	}
</style>
