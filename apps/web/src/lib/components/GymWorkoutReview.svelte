<script lang="ts">
	import type { RoutineAdherence, SetAdherenceStatus } from '$lib/gym/gym_adherence';
	import type { GymStepResult, NextTargetHint } from '$lib/gym/gym_session_types';
	import { formatWeight } from '$lib/format/units.svelte';
	import { m as t } from '$lib/i18n/store.svelte';

	interface Props {
		adherence: RoutineAdherence | null;
		stepResults: GymStepResult[];
		/// P4 next-target hints, one per scheme-tracked exercise. Empty for an
		/// ad-hoc or no-progression session — the section self-hides.
		nextTargets?: NextTargetHint[];
	}

	let { adherence, stepResults, nextTargets = [] }: Props = $props();

	// Headline reason + a concrete delta ("+5 kg" / "rep climb 8→9"). Neutral /
	// positive treatment — never the red/amber adherence colours.
	function hintReason(h: NextTargetHint): string {
		return t(`gym.routine.nextTarget.${h.reason}`);
	}
	function hintDelta(h: NextTargetHint): string | null {
		if (
			h.reason === 'increase_weight' &&
			h.suggestedWeightKg != null &&
			h.currentTopKg != null &&
			h.suggestedWeightKg !== h.currentTopKg
		) {
			const d = h.suggestedWeightKg - h.currentTopKg;
			return `${d > 0 ? '+' : '−'}${formatWeight(Math.abs(d))}`;
		}
		if (h.reason === 'deload' && h.suggestedWeightKg != null && h.currentTopKg != null) {
			const d = h.suggestedWeightKg - h.currentTopKg;
			return `${d > 0 ? '+' : '−'}${formatWeight(Math.abs(d))}`;
		}
		if (h.reason === 'increase_reps' && h.currentTopReps != null) {
			const to = h.currentTopReps + 1;
			return t('gym.routine.nextTarget.repClimb', { from: h.currentTopReps, to });
		}
		return null;
	}

	const hasData = $derived(!!adherence && stepResults.length > 0);

	const STATUS_ICON: Record<SetAdherenceStatus, string> = {
		hit: 'check_circle',
		partial: 'error',
		missed: 'cancel',
		extra: 'add_circle',
	};

	function statusLabel(s: SetAdherenceStatus): string {
		return s === 'hit'
			? t('gym.review.status.hit')
			: s === 'partial'
				? t('gym.review.status.partial')
				: s === 'missed'
					? t('gym.review.status.missed')
					: t('gym.review.status.extra');
	}

	function repWeight(
		reps: number | null,
		repsMax: number | null,
		weightKg: number | null,
		durationS: number | null,
	): string {
		const parts: string[] = [];
		if (reps != null) {
			parts.push(repsMax != null && repsMax !== reps ? `${reps}–${repsMax}` : String(reps));
		}
		if (weightKg != null) parts.push(formatWeight(weightKg));
		const rw = parts.join(' × ');
		if (durationS != null) {
			const dur = t('gym.durationValue', { seconds: durationS });
			return rw ? `${rw} · ${dur}` : dur;
		}
		return rw || '—';
	}

	function verdictKey(v: RoutineAdherence['verdict']): string {
		return v === 'completed'
			? t('gym.review.verdict.completed')
			: v === 'partial'
				? t('gym.review.verdict.partial')
				: t('gym.review.verdict.abandoned');
	}

	const adherencePctRounded = $derived(
		adherence ? Math.round(adherence.adherencePct * 100) : 0,
	);

	// Stable display order — planned sets keep their result order; 'extra'
	// logged sets sort to the end.
	const ordered = $derived.by(() => {
		const planned = stepResults.filter((s) => s.status !== 'extra');
		const extra = stepResults.filter((s) => s.status === 'extra');
		return [...planned, ...extra];
	});
</script>

{#if hasData && adherence}
	<section class="card-elevated review" data-testid="gym-workout-review">
		<div class="review-head">
			<h2>{t('gym.review.title')}</h2>
			<div class="verdict-group">
				<span class="adherence-pct" data-testid="gym-review-pct">
					{t('gym.review.adherence', { pct: adherencePctRounded })}
				</span>
				<span class="verdict verdict-{adherence.verdict}" data-testid="gym-review-verdict">
					{verdictKey(adherence.verdict)}
				</span>
			</div>
		</div>
		<table class="review-table">
			<thead>
				<tr>
					<th></th>
					<th class="section-label">{t('gym.review.planned')}</th>
					<th class="section-label">{t('gym.review.actual')}</th>
				</tr>
			</thead>
			<tbody>
				{#each ordered as s (s.exercise_key + ':' + s.set_index + ':' + s.status)}
					<tr>
						<td class="status-cell">
							<span class="status-pill status-{s.status}">
								<span class="material-symbols" aria-hidden="true">{STATUS_ICON[s.status]}</span>
								{statusLabel(s.status)}
							</span>
						</td>
						<td class="num">
							{s.status === 'extra'
								? '—'
								: repWeight(s.target_reps_min, s.target_reps_max, s.target_weight_kg, s.target_duration_s)}
						</td>
						<td class="num">
							{repWeight(s.actual_reps, null, s.actual_weight_kg, s.actual_duration_s)}
						</td>
					</tr>
				{/each}
			</tbody>
		</table>

		{#if nextTargets.length > 0}
			<div class="next-targets" data-testid="gym-next-targets">
				<span class="next-head section-label">{t('gym.routine.nextTarget')}</span>
				<ul class="next-list">
					{#each nextTargets as h (h.exerciseKey)}
						<li class="next-chip" data-testid="gym-next-target">
							<span class="material-symbols" aria-hidden="true">
								{h.reason === 'deload' ? 'trending_down' : 'trending_up'}
							</span>
							<span class="next-name">{h.exerciseName}</span>
							{#if hintDelta(h)}
								<span class="next-delta">{hintDelta(h)}</span>
							{/if}
							<span class="next-reason">{hintReason(h)}</span>
						</li>
					{/each}
				</ul>
			</div>
		{/if}
	</section>
{/if}

<style>
	.review {
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-md);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.next-targets {
		display: flex;
		flex-direction: column;
		gap: var(--space-xs);
		border-top: 1px solid var(--color-border);
		padding-top: var(--space-md);
	}
	.next-head {
		color: var(--color-text-tertiary);
	}
	.next-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-xs);
	}
	.next-chip {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.78rem;
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
		color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.next-chip .material-symbols {
		font-size: 0.95rem;
	}
	.next-name {
		font-weight: 600;
	}
	.next-delta {
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.next-reason {
		color: var(--color-text-secondary);
	}
	.review-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.review-head h2 {
		margin: 0;
		font-size: 1.1rem;
		font-weight: 600;
	}
	.verdict-group {
		display: inline-flex;
		align-items: center;
		gap: var(--space-sm);
	}
	.adherence-pct {
		font-size: 1.1rem;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.verdict {
		font-size: 0.72rem;
		font-weight: 700;
		letter-spacing: 0.04em;
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
	}
	.verdict-completed {
		color: var(--color-success-strong);
		background: var(--color-success-light);
	}
	.verdict-partial {
		color: var(--color-warning-strong);
		background: var(--color-warning-light, rgba(230, 169, 107, 0.16));
	}
	.verdict-abandoned {
		color: var(--color-text-secondary);
		background: var(--color-bg-secondary);
	}

	.review-table {
		border-collapse: collapse;
		width: 100%;
	}
	.review-table th {
		text-align: start;
		padding: var(--space-2xs) var(--space-sm);
		color: var(--color-text-tertiary);
	}
	.review-table th.section-label {
		text-align: end;
	}
	.review-table td {
		padding: var(--space-xs) var(--space-sm);
		border-top: 1px solid var(--color-border);
	}
	.num {
		text-align: end;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.status-cell {
		width: 1%;
	}
	.status-pill {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2xs);
		font-size: 0.72rem;
		font-weight: 700;
		padding: var(--space-2xs) var(--space-sm);
		border-radius: var(--radius-sm);
		white-space: nowrap;
	}
	.status-pill .material-symbols {
		font-size: 0.9rem;
	}
	.status-hit {
		color: var(--color-success-strong);
		background: var(--color-success-light);
	}
	.status-partial {
		color: var(--color-warning-strong);
		background: var(--color-warning-light, rgba(230, 169, 107, 0.16));
	}
	.status-missed {
		color: var(--color-danger);
		background: var(--color-danger-light);
	}
	.status-extra {
		color: var(--color-text-secondary);
		background: var(--color-bg-secondary);
	}
</style>
