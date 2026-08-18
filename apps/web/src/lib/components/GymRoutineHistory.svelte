<script lang="ts">
	import { fetchGymRoutineHistory } from '$lib/core/data';
	import {
		routineHistoryFromAggregate,
		type RoutineHistory,
		type RoutineSessionVerdict,
	} from '$lib/gym/routine_history';
	import { formatDate } from '$lib/format/time';
	import { m as t } from '$lib/i18n/store.svelte';

	interface Props {
		routineId: string;
	}

	let { routineId }: Props = $props();

	const RECENT_LIMIT = 5;

	let history = $state<RoutineHistory | null>(null);
	let loadError = $state(false);
	// Navigating between two routines reuses this component, so a slow read for
	// the routine just left can resolve after the new one and publish the wrong
	// history under the new title. Only the newest read may write.
	let readToken = 0;

	// The panel owns its own read so a history failure can't blank the
	// prescription the page exists to show (conventions.md § Layered resilience).
	async function load() {
		if (!routineId) return;
		const token = ++readToken;
		// Drop the outgoing routine's numbers before the new ones arrive, or the
		// panel reads them under the new routine's title for a beat.
		history = null;
		loadError = false;
		try {
			const agg = await fetchGymRoutineHistory(routineId, RECENT_LIMIT);
			if (token !== readToken) return;
			history = routineHistoryFromAggregate(agg, Date.now());
		} catch (e) {
			if (token !== readToken) return;
			console.debug('routine history load failed', e);
			history = null;
			loadError = true;
		}
	}

	$effect(() => {
		void load();
	});

	function verdictLabel(v: RoutineSessionVerdict): string {
		return v === 'completed'
			? t('gym.review.verdict.completed')
			: v === 'partial'
				? t('gym.review.verdict.partial')
				: v === 'abandoned'
					? t('gym.review.verdict.abandoned')
					: t('gym.routine.history.verdict.ungraded');
	}

	const recent = $derived(history?.recentSessions ?? []);
</script>

{#if loadError}
	<section class="card-elevated history" data-testid="routine-history-error">
		<p role="alert">{t('gym.routine.history.loadError')}</p>
		<button class="btn btn-outline" onclick={load}>{t('gym.routine.retry')}</button>
	</section>
{:else if history && history.sessionCount > 0}
	<section class="card-elevated history" aria-labelledby="routine-history-head" data-testid="routine-history">
		<div class="history-head">
			<h2 id="routine-history-head">{t('gym.routine.history.title')}</h2>
			<span class="history-count" data-testid="routine-history-count">
				{history.sessionCount === 1
					? t('gym.records.sessionsOne')
					: t('gym.records.sessionsMany', { count: history.sessionCount })}
			</span>
		</div>

		<p class="history-stats">
			<span data-testid="routine-history-last">
				{t('gym.routine.history.lastDone', { days: history.daysSinceLast ?? 0 })}
			</span>
			{#if history.gradedCount > 0}
				<span class="stat-sep" aria-hidden="true">·</span>
				<span data-testid="routine-history-rate">
					{t('gym.routine.history.completedRate', {
						completed: history.completedCount,
						graded: history.gradedCount,
					})}
				</span>
			{/if}
		</p>

		<h3 class="section-label">{t('gym.routine.history.recent')}</h3>
		<ul class="session-list">
			{#each recent as s (s.id)}
				<li>
					<a class="session-row" href="/gym/{s.id}">
						<span class="session-date">{formatDate(s.startedAt)}</span>
						<span class="session-title">{s.title || t('gym.untitled')}</span>
						<span class="verdict verdict-{s.verdict}">{verdictLabel(s.verdict)}</span>
					</a>
				</li>
			{/each}
		</ul>
	</section>
{/if}

<style>
	.history {
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.history-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.history-head h2 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
	}
	.history-count {
		color: var(--color-text-tertiary);
		font-size: 0.9rem;
	}
	.history-stats {
		margin: 0;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
	}
	.stat-sep {
		margin: 0 var(--space-2xs);
		color: var(--color-text-tertiary);
	}
	.session-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
	}
	.session-row {
		display: flex;
		align-items: center;
		gap: var(--space-sm);
		padding: var(--space-xs) var(--space-sm);
		border-radius: var(--radius-sm);
		color: inherit;
		text-decoration: none;
	}
	.session-row:hover,
	.session-row:focus-visible {
		background: var(--color-bg-secondary);
	}
	.session-date {
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.session-title {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--color-text-secondary);
	}
	.verdict {
		font-size: 0.72rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
		white-space: nowrap;
	}
	.verdict-completed {
		color: color-mix(in srgb, var(--color-success) 50%, var(--color-text));
		background: var(--color-success-light);
	}
	.verdict-partial {
		color: color-mix(in srgb, var(--color-warning) 45%, var(--color-text));
		background: var(--color-warning-light);
	}
	.verdict-abandoned {
		color: var(--color-text-secondary);
		background: var(--color-bg-secondary);
	}
	.verdict-ungraded {
		color: var(--color-text-tertiary);
		border: 1px solid var(--color-border);
	}
</style>
