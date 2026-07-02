<script lang="ts">
	import type { PlanWorkout, PlanWeek } from '$lib/types';
	import {
		addDays,
		isWorkoutCompleted,
		isWorkoutSkipped,
		parseISO,
		formatISO
	} from '$lib/training/training';
	import { workoutKindLabel } from '$lib/training/workout_labels';
	import { fmtKm } from '$lib/format/units.svelte';
	import { m } from '$lib/i18n/store.svelte';
	import type { WeekStart } from '$lib/format/calendar';

	type Props = {
		/// The plan's start date (yyyy-mm-dd). The strip's 7-day window is
		/// derived from `currentWeek.week_index * 7` off this — NOT from the
		/// real calendar week — so its completion count matches the week card.
		startDate: string;
		/// The current week row (or null when the plan hasn't started / has
		/// no weeks). Drives both the day window and the displayed workouts.
		currentWeek: PlanWeek | null;
		/// The workouts belonging to `currentWeek` (the same list the week
		/// card counts), keyed onto days by `scheduled_date`.
		weekWorkouts: PlanWorkout[];
		/// Today's local ISO date — highlights the matching cell.
		today: string;
		/// First day of the week for display ordering only.
		weekStart?: WeekStart;
		/// Called when a workout cell is clicked (opens the inline editor).
		onSelect?: (workout: PlanWorkout) => void;
	};
	let { startDate, currentWeek, weekWorkouts, today, weekStart = 'monday', onSelect }: Props =
		$props();

	const KIND_COLOR: Record<string, string> = {
		easy: 'var(--color-text-secondary)',
		long: 'var(--color-primary)',
		recovery: 'var(--color-text-tertiary)',
		tempo: '#C98ECF',
		interval: '#D97A54',
		marathon_pace: '#E6A96B',
		race: 'var(--color-primary)',
		rest: 'var(--color-border)'
	};

	const DOW_KEYS = [
		'planDetail.dowSun',
		'planDetail.dowMon',
		'planDetail.dowTue',
		'planDetail.dowWed',
		'planDetail.dowThu',
		'planDetail.dowFri',
		'planDetail.dowSat'
	] as const;

	let workoutByDate = $derived.by(() => {
		const map = new Map<string, PlanWorkout>();
		for (const w of weekWorkouts) map.set(w.scheduled_date, w);
		return map;
	});

	type Cell = { iso: string; dow: string; workout: PlanWorkout | null };

	/// The seven cells of `currentWeek`, anchored to `start_date +
	/// week_index*7` and re-ordered for display by `weekStart`. The window
	/// is the plan's week bucket, so the workouts shown are exactly the ones
	/// the week card counts — ordering is presentation only.
	let cells = $derived.by<Cell[]>(() => {
		if (!currentWeek) return [];
		const weekStartD = addDays(parseISO(startDate), currentWeek.week_index * 7);
		const out: Cell[] = [];
		for (let i = 0; i < 7; i++) {
			const d = addDays(weekStartD, i);
			const iso = formatISO(d);
			out.push({ iso, dow: m(DOW_KEYS[d.getDay()]), workout: workoutByDate.get(iso) ?? null });
		}
		// Re-order so the row begins on the chosen week start (display only).
		if (weekStart === 'sunday') {
			const idx = out.findIndex((c) => parseISO(c.iso).getDay() === 0);
			if (idx > 0) return [...out.slice(idx), ...out.slice(0, idx)];
		}
		return out;
	});

	let doneCount = $derived(weekWorkouts.filter(isWorkoutCompleted).length);
	let activeCount = $derived(
		weekWorkouts.filter((w) => w.kind !== 'rest' && !isWorkoutSkipped(w)).length
	);
</script>

{#if currentWeek}
	<section class="strip" aria-label={m('planDetail.currentWeek')}>
		<div class="strip-head">
			<h2 class="strip-title">{m('planDetail.currentWeek')}</h2>
			<span class="strip-count">
				{doneCount}<em> / {activeCount}</em> {m('planDetail.done')}
			</span>
		</div>
		<div class="strip-row">
			{#each cells as c (c.iso)}
				{@const wo = c.workout}
				{#if wo}
					<svelte:element
						this={onSelect ? 'button' : 'a'}
						role={onSelect ? 'button' : 'link'}
						type={onSelect ? 'button' : undefined}
						onclick={onSelect ? () => onSelect(wo) : undefined}
						class="day has-workout"
						class:today={c.iso === today}
						class:done={isWorkoutCompleted(wo)}
						class:rest={wo.kind === 'rest'}
						style="--kind: {KIND_COLOR[wo.kind] ?? 'var(--color-text-secondary)'}"
						aria-label={`${c.dow}: ${workoutKindLabel(wo.kind)}${
							isWorkoutCompleted(wo) ? m('planDetail.ariaCompletedSuffix') : ''
						}`}
					>
						<span class="dow">{c.dow}</span>
						<span class="kind">{workoutKindLabel(wo.kind)}</span>
						{#if wo.target_distance_m != null && wo.kind !== 'rest'}
							<span class="dist">{fmtKm(wo.target_distance_m, 1)}</span>
						{/if}
						{#if isWorkoutCompleted(wo)}
							<span class="material-symbols check" aria-hidden="true">check_circle</span>
						{/if}
					</svelte:element>
				{:else}
					<div class="day empty" class:today={c.iso === today}>
						<span class="dow">{c.dow}</span>
					</div>
				{/if}
			{/each}
		</div>
	</section>
{/if}

<style>
	.strip {
		margin-bottom: var(--space-md);
	}
	.strip-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		margin-bottom: var(--space-xs);
	}
	.strip-title {
		font-size: 0.95rem;
		font-weight: 600;
		margin: 0;
	}
	.strip-count {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.strip-count em {
		font-style: normal;
		color: var(--color-text-tertiary);
	}
	.strip-row {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		gap: 0.35rem;
	}
	.day {
		min-height: 4rem;
		padding: 0.35rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		font-size: 0.7rem;
		color: var(--color-text);
		text-decoration: none;
		position: relative;
	}
	.day.empty {
		background: transparent;
		opacity: 0.55;
	}
	.day.today {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 1px var(--color-primary);
	}
	.day.has-workout {
		border-inline-start: 3px solid var(--kind);
		cursor: pointer;
		transition: transform var(--transition-fast), box-shadow var(--transition-fast);
	}
	.day.has-workout:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-sm);
	}
	.day.done {
		background: var(--color-success-light);
	}
	.dow {
		font-size: 0.65rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.kind {
		font-size: 0.65rem;
		font-weight: 700;
		color: var(--kind);
		text-transform: uppercase;
		letter-spacing: 0.04em;
		line-height: 1.1;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.dist {
		font-size: 0.7rem;
		color: var(--color-text);
		font-weight: 600;
	}
	.check {
		position: absolute;
		bottom: 0.3rem;
		inset-inline-end: 0.3rem;
		font-family: 'Material Symbols Outlined';
		font-size: 0.95rem;
		color: var(--color-success);
	}
	@media (max-width: 40rem) {
		.day {
			min-height: 3.25rem;
			padding: 0.25rem;
		}
		.kind {
			font-size: 0.55rem;
		}
		.dist {
			font-size: 0.6rem;
		}
	}
</style>
