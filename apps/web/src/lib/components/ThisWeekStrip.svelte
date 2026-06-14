<script lang="ts">
	import { currentWeek, type WeekActivity, type WeekStart } from '$lib/training/current_week';
	import { weekdayAbbrevs } from '$lib/format/calendar';
	import { fmtKm } from '$lib/format/units.svelte';
	import { m, currentLocale } from '$lib/i18n/store.svelte';

	type Props = {
		/// The runner's logged activities — the dashboard passes its
		/// already-fetched, source-filtered run list straight in. Only
		/// `started_at` + `distance_m` are read.
		activities: WeekActivity[];
		/// First day of the week (the `week_start_day` pref). Drives both
		/// the day window and the label ordering.
		weekStart?: WeekStart;
		/// Today's clock — injectable for tests / SSR determinism.
		now?: Date;
	};
	let { activities, weekStart = 'monday', now = new Date() }: Props = $props();

	let week = $derived(currentWeek(activities, weekStart, now));

	/// Localized short weekday labels, ordered to begin on `weekStart`, so
	/// the row reads Mon→Sun (or Sun→Sat) in the active locale. The strip's
	/// cells are already in week order, so this lines up by index.
	let dowLabels = $derived(weekdayAbbrevs(weekStart, currentLocale()));

	/// The busiest day's distance — scales every bar so the heaviest day
	/// fills the track and the rest read relative to it. A zeroed week
	/// leaves every bar empty.
	let maxDistance = $derived(Math.max(0, ...week.days.map((d) => d.distanceM)));

	function barPct(distanceM: number): number {
		if (maxDistance <= 0 || distanceM <= 0) return 0;
		// Floor a logged-but-tiny day at a visible sliver.
		return Math.max(8, Math.round((distanceM / maxDistance) * 100));
	}
</script>

<section class="week-strip" aria-label={m('dash.weekStripTitle')}>
	<div class="week-strip-head">
		<h2 class="week-strip-title">{m('dash.weekStripTitle')}</h2>
		<span class="week-strip-total">
			{fmtKm(week.totalDistanceM)}
			<em>
				· {week.totalCount === 1
					? m('dash.activityCountOne', { n: week.totalCount })
					: m('dash.activityCountOther', { n: week.totalCount })}
			</em>
		</span>
	</div>
	<div class="week-strip-row">
		{#each week.days as day, i (day.iso)}
			<div
				class="day"
				class:today={day.isToday}
				class:future={day.isFuture}
				class:logged={day.count > 0}
				aria-label={day.count > 0
					? m('dash.weekStripDayAria', { dow: dowLabels[i], dist: fmtKm(day.distanceM) })
					: m('dash.weekStripDayRestAria', { dow: dowLabels[i] })}
			>
				<span class="day-dow">{dowLabels[i]}</span>
				<div class="day-bar-track" aria-hidden="true">
					<span class="day-bar" style="height: {barPct(day.distanceM)}%"></span>
				</div>
				<span class="day-dist">
					{#if day.count > 0}{fmtKm(day.distanceM)}{:else}<span class="day-rest">·</span>{/if}
				</span>
			</div>
		{/each}
	</div>
</section>

<style>
	.week-strip {
		margin-bottom: var(--space-md);
	}
	.week-strip-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		margin-bottom: var(--space-xs);
	}
	.week-strip-title {
		font-size: 0.95rem;
		font-weight: 600;
		margin: 0;
	}
	.week-strip-total {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.week-strip-total em {
		font-style: normal;
		color: var(--color-text-tertiary);
	}
	.week-strip-row {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		gap: 0.35rem;
	}
	.day {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 0.3rem;
		padding: 0.4rem 0.2rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		min-height: 5rem;
	}
	.day.future {
		opacity: 0.55;
	}
	.day.today {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 1px var(--color-primary);
	}
	.day.logged {
		background: var(--color-success-light);
	}
	.day-dow {
		font-size: 0.65rem;
		font-weight: 600;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.day-bar-track {
		flex: 1;
		width: 0.5rem;
		display: flex;
		align-items: flex-end;
		justify-content: center;
		min-height: 2rem;
	}
	.day-bar {
		width: 100%;
		min-height: 0;
		background: var(--color-primary);
		border-radius: var(--radius-sm);
		transition: height var(--transition-fast);
	}
	.day-dist {
		font-size: 0.65rem;
		font-weight: 600;
		color: var(--color-text);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.day-rest {
		color: var(--color-text-tertiary);
	}
	@media (max-width: 40rem) {
		.day {
			min-height: 4.25rem;
			padding: 0.3rem 0.1rem;
		}
		.day-dist {
			font-size: 0.55rem;
		}
	}
</style>
