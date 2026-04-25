<script lang="ts">
	import type { PlanWorkout } from '$lib/types';
	import { fmtKm, WORKOUT_KIND_LABEL, parseISO, todayISO } from '$lib/training';

	type Props = {
		startDate: string;
		endDate: string;
		workouts: PlanWorkout[];
		planId: string;
	};
	let { startDate, endDate, workouts, planId }: Props = $props();

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

	let workoutByDate = $derived.by(() => {
		const m = new Map<string, PlanWorkout>();
		for (const w of workouts) m.set(w.scheduled_date, w);
		return m;
	});

	let months = $derived.by(() => {
		const out: { year: number; month: number }[] = [];
		const start = parseISO(startDate);
		const end = parseISO(endDate);
		let y = start.getFullYear();
		let m = start.getMonth();
		while (y < end.getFullYear() || (y === end.getFullYear() && m <= end.getMonth())) {
			out.push({ year: y, month: m });
			m += 1;
			if (m > 11) { m = 0; y += 1; }
		}
		return out;
	});

	function initialIdx(): number {
		const today = new Date();
		const idx = months.findIndex(
			({ year, month }) => year === today.getFullYear() && month === today.getMonth()
		);
		return idx >= 0 ? idx : 0;
	}

	let currentIdx = $state(initialIdx());

	let current = $derived(months[currentIdx]);

	let today = $derived(todayISO());

	type Cell = {
		iso: string;
		day: number;
		inMonth: boolean;
		inPlan: boolean;
	};

	function isoFor(year: number, month: number, day: number): string {
		const mm = String(month + 1).padStart(2, '0');
		const dd = String(day).padStart(2, '0');
		return `${year}-${mm}-${dd}`;
	}

	let grid = $derived.by<Cell[]>(() => {
		if (!current) return [];
		const { year, month } = current;
		const first = new Date(year, month, 1);
		const last = new Date(year, month + 1, 0);
		// Monday-first (matches the rest of the app — week_start_day default)
		const leadDow = (first.getDay() + 6) % 7;
		const cells: Cell[] = [];

		const prevLast = new Date(year, month, 0).getDate();
		for (let i = leadDow; i > 0; i--) {
			const d = prevLast - i + 1;
			const prevMonth = month === 0 ? 11 : month - 1;
			const prevYear = month === 0 ? year - 1 : year;
			const iso = isoFor(prevYear, prevMonth, d);
			cells.push({ iso, day: d, inMonth: false, inPlan: iso >= startDate && iso <= endDate });
		}
		for (let d = 1; d <= last.getDate(); d++) {
			const iso = isoFor(year, month, d);
			cells.push({ iso, day: d, inMonth: true, inPlan: iso >= startDate && iso <= endDate });
		}
		// Pad to a 7-column-wide rectangle
		const remainder = cells.length % 7;
		if (remainder !== 0) {
			const trail = 7 - remainder;
			for (let d = 1; d <= trail; d++) {
				const nextMonth = month === 11 ? 0 : month + 1;
				const nextYear = month === 11 ? year + 1 : year;
				const iso = isoFor(nextYear, nextMonth, d);
				cells.push({ iso, day: d, inMonth: false, inPlan: iso >= startDate && iso <= endDate });
			}
		}
		return cells;
	});

	const MONTH_LABELS = [
		'January', 'February', 'March', 'April', 'May', 'June',
		'July', 'August', 'September', 'October', 'November', 'December'
	];
	const DOW = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

	function prev() {
		if (currentIdx > 0) currentIdx -= 1;
	}
	function next() {
		if (currentIdx < months.length - 1) currentIdx += 1;
	}
</script>

<div class="cal">
	<header class="cal-head">
		<button
			type="button"
			class="nav"
			onclick={prev}
			disabled={currentIdx === 0}
			aria-label="Previous month"
		>
			<span class="material-symbols">chevron_left</span>
		</button>
		<h3>{MONTH_LABELS[current.month]} {current.year}</h3>
		<button
			type="button"
			class="nav"
			onclick={next}
			disabled={currentIdx === months.length - 1}
			aria-label="Next month"
		>
			<span class="material-symbols">chevron_right</span>
		</button>
	</header>

	<div class="dow-row">
		{#each DOW as d}
			<span>{d}</span>
		{/each}
	</div>

	<div class="grid">
		{#each grid as c (c.iso)}
			{@const wo = workoutByDate.get(c.iso)}
			{#if wo && c.inPlan}
				<a
					href="/plans/{planId}/workouts/{wo.id}"
					class="cell has-workout"
					class:out-month={!c.inMonth}
					class:today={c.iso === today}
					class:done={!!wo.completed_run_id}
					style="--kind: {KIND_COLOR[wo.kind] ?? 'var(--color-text-secondary)'}"
				>
					<span class="day-num">{c.day}</span>
					<span class="kind-pill">
						{WORKOUT_KIND_LABEL[wo.kind as keyof typeof WORKOUT_KIND_LABEL] ?? wo.kind}
					</span>
					{#if wo.target_distance_m != null && wo.kind !== 'rest'}
						<span class="dist">{fmtKm(wo.target_distance_m, 1)}</span>
					{/if}
					{#if wo.completed_run_id}
						<span class="material-symbols check">check_circle</span>
					{/if}
				</a>
			{:else}
				<div
					class="cell"
					class:out-month={!c.inMonth}
					class:out-plan={!c.inPlan}
					class:today={c.iso === today}
				>
					<span class="day-num">{c.day}</span>
				</div>
			{/if}
		{/each}
	</div>
</div>

<style>
	.cal {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
	}
	.cal-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: var(--space-md);
	}
	.cal-head h3 {
		font-size: 1rem;
		font-weight: 600;
	}
	.nav {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 2rem;
		height: 2rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}
	.nav:hover:not(:disabled) {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}
	.nav:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.nav .material-symbols {
		font-size: 1.2rem;
	}
	.dow-row {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		gap: 0.35rem;
		margin-bottom: 0.4rem;
		text-align: center;
		font-size: 0.7rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--color-text-tertiary);
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		gap: 0.35rem;
	}
	.cell {
		min-height: 4.5rem;
		padding: 0.35rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		font-size: 0.7rem;
		color: var(--color-text);
		text-decoration: none;
		position: relative;
	}
	.cell.out-month {
		opacity: 0.35;
	}
	.cell.out-plan {
		background: transparent;
		border-color: transparent;
	}
	.cell.today {
		border-color: var(--color-primary);
		box-shadow: 0 0 0 1px var(--color-primary);
	}
	.cell.has-workout {
		border-left: 3px solid var(--kind);
		cursor: pointer;
		transition: transform var(--transition-fast), box-shadow var(--transition-fast);
	}
	.cell.has-workout:hover {
		transform: translateY(-1px);
		box-shadow: var(--shadow-sm);
	}
	.cell.done {
		background: var(--color-success-light);
	}
	.day-num {
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text-secondary);
		align-self: flex-end;
	}
	.kind-pill {
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
		right: 0.3rem;
		font-family: 'Material Symbols Outlined';
		font-size: 0.95rem;
		color: var(--color-success);
	}
	@media (max-width: 40rem) {
		.cell {
			min-height: 3.5rem;
			padding: 0.2rem;
		}
		.kind-pill {
			font-size: 0.55rem;
		}
		.dist {
			font-size: 0.6rem;
		}
	}
</style>
