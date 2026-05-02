<script lang="ts">
	import Modal from './Modal.svelte';

	interface Props {
		open: boolean;
		onclose: () => void;
		/** ISO yyyy-mm-dd (HTML date input format). */
		initialFrom?: string;
		initialTo?: string;
		/** Called when the user taps Apply with both endpoints set. */
		onapply: (from: string, to: string) => void;
		/** Called when the user taps Clear. The modal stays open so they
		 *  can pick again without re-opening it. */
		onclear?: () => void;
	}

	let { open, onclose, initialFrom, initialTo, onapply, onclear }: Props = $props();

	const MONTH_NAMES = [
		'January', 'February', 'March', 'April', 'May', 'June',
		'July', 'August', 'September', 'October', 'November', 'December',
	];
	const DOW_LABELS = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

	function parseIso(s: string | undefined): Date | null {
		if (!s) return null;
		// Treat as local-midnight so cell comparisons line up with the
		// Date objects we mint client-side.
		const d = new Date(s + 'T00:00:00');
		return isNaN(d.getTime()) ? null : d;
	}

	function toIso(d: Date): string {
		const y = d.getFullYear();
		const m = String(d.getMonth() + 1).padStart(2, '0');
		const day = String(d.getDate()).padStart(2, '0');
		return `${y}-${m}-${day}`;
	}

	function sameDay(a: Date, b: Date): boolean {
		return (
			a.getFullYear() === b.getFullYear() &&
			a.getMonth() === b.getMonth() &&
			a.getDate() === b.getDate()
		);
	}

	let pendingFrom = $state<Date | null>(null);
	let pendingTo = $state<Date | null>(null);
	let monthsEl: HTMLDivElement | undefined = $state();

	// Reset pending state every time the modal re-opens, hydrating from
	// the latest props. Without this, a closed-and-reopened modal would
	// silently keep stale picks from a previous session.
	// Also scrolls the months list to wherever the user was last
	// looking — pendingFrom if set, otherwise the current month — so a
	// reopen doesn't dump them at the very top of the 3-year range.
	$effect(() => {
		if (open) {
			pendingFrom = parseIso(initialFrom);
			pendingTo = parseIso(initialTo);
			queueMicrotask(() => scrollToMonth(pendingFrom ?? today));
		}
	});

	const today = new Date();
	const firstMonth = new Date(today.getFullYear() - 2, today.getMonth(), 1);
	const lastMonth = new Date(today.getFullYear() + 1, today.getMonth(), 1);
	const monthCount =
		(lastMonth.getFullYear() - firstMonth.getFullYear()) * 12 +
		(lastMonth.getMonth() - firstMonth.getMonth()) +
		1;

	function monthAt(i: number): Date {
		const yr = firstMonth.getFullYear() + Math.floor((firstMonth.getMonth() + i) / 12);
		const mo = (firstMonth.getMonth() + i) % 12;
		return new Date(yr, mo, 1);
	}

	function monthIndex(target: Date): number {
		return (
			(target.getFullYear() - firstMonth.getFullYear()) * 12 +
			(target.getMonth() - firstMonth.getMonth())
		);
	}

	function scrollToMonth(target: Date): void {
		if (!monthsEl) return;
		const idx = monthIndex(target);
		const clamped = Math.max(0, Math.min(monthCount - 1, idx));
		const section = monthsEl.querySelector<HTMLElement>(
			`[data-month-idx="${clamped}"]`,
		);
		section?.scrollIntoView({ block: 'start' });
	}

	/// List of years spanned by the scrollable range. Drives the year
	/// jumper at the top so the user doesn't have to scroll through 36
	/// months to get from May 2026 back to March 2024.
	const yearOptions: number[] = (() => {
		const out: number[] = [];
		for (let y = firstMonth.getFullYear(); y <= lastMonth.getFullYear(); y++) {
			out.push(y);
		}
		return out;
	})();

	/// Year currently anchored at the top of the visible months list.
	/// Tracked so the dropdown reflects where the user has scrolled to
	/// — otherwise picking "2025" twice in a row would feel like a no-op
	/// after they'd manually scrolled away from January 2025.
	let visibleYear = $state(today.getFullYear());

	function jumpToYear(y: number): void {
		// Land on the current month if jumping to the active year
		// (so "2026" with today = May 2026 lands on May, not January).
		// Otherwise land on January of the chosen year.
		const target =
			y === today.getFullYear()
				? new Date(y, today.getMonth(), 1)
				: new Date(y, 0, 1);
		scrollToMonth(target);
		visibleYear = y;
	}

	function onMonthsScroll(): void {
		if (!monthsEl) return;
		// Find the first month section whose top is at or above the
		// scroll viewport's top edge — that's the one anchoring the view.
		const sections = monthsEl.querySelectorAll<HTMLElement>('[data-month-idx]');
		for (const s of sections) {
			const rect = s.getBoundingClientRect();
			const containerTop = monthsEl.getBoundingClientRect().top;
			if (rect.bottom > containerTop + 4) {
				const idx = Number(s.dataset.monthIdx);
				visibleYear = monthAt(idx).getFullYear();
				return;
			}
		}
	}

	function selectingEnd(): boolean {
		return pendingFrom !== null && pendingTo === null;
	}

	function onTapDate(d: Date): void {
		if (pendingFrom && pendingTo) {
			pendingFrom = d;
			pendingTo = null;
			return;
		}
		if (!pendingFrom) {
			pendingFrom = d;
			return;
		}
		// Start is set, picking the end. Swap on inverted picks instead
		// of rejecting — feels more forgiving than ignoring the click.
		if (d < pendingFrom) {
			pendingTo = pendingFrom;
			pendingFrom = d;
		} else {
			pendingTo = d;
		}
	}

	function clearPending(): void {
		pendingFrom = null;
		pendingTo = null;
		onclear?.();
	}

	function apply(): void {
		if (!pendingFrom || !pendingTo) return;
		onapply(toIso(pendingFrom), toIso(pendingTo));
	}

	function formatChip(d: Date): string {
		const dows = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
		const months = [
			'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
			'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
		];
		// Date.getDay() returns 0=Sun..6=Sat; remap to 0=Mon..6=Sun.
		const dowIdx = (d.getDay() + 6) % 7;
		const base = `${dows[dowIdx]}, ${months[d.getMonth()]} ${d.getDate()}`;
		return d.getFullYear() === today.getFullYear() ? base : `${base}, ${d.getFullYear()}`;
	}

	let canApply = $derived(pendingFrom !== null && pendingTo !== null);
	let activeStart = $derived(pendingFrom === null || !selectingEnd());
</script>

<Modal {open} {onclose} title="Select dates" bodyClass="range-body">
	<div class="range-picker">
		<div class="chip-row">
			<div class="chip" class:active={activeStart}>
				<span class="chip-label">START</span>
				<span class="chip-value">
					{pendingFrom ? formatChip(pendingFrom) : 'Tap a date'}
				</span>
			</div>
			<div class="chip" class:active={!activeStart}>
				<span class="chip-label">END</span>
				<span class="chip-value">
					{pendingTo ? formatChip(pendingTo) : 'Tap a date'}
				</span>
			</div>
		</div>

		<div class="jumper-row">
			<button
				type="button"
				class="jumper-btn"
				aria-label="Previous year"
				onclick={() => jumpToYear(Math.max(yearOptions[0], visibleYear - 1))}
				disabled={visibleYear <= yearOptions[0]}
			>
				<span class="material-symbols">chevron_left</span>
			</button>
			<select
				class="jumper-select"
				aria-label="Jump to year"
				value={visibleYear}
				onchange={(e) => jumpToYear(Number((e.currentTarget as HTMLSelectElement).value))}
			>
				{#each yearOptions as y (y)}
					<option value={y}>{y}</option>
				{/each}
			</select>
			<button
				type="button"
				class="jumper-btn"
				aria-label="Next year"
				onclick={() => jumpToYear(Math.min(yearOptions[yearOptions.length - 1], visibleYear + 1))}
				disabled={visibleYear >= yearOptions[yearOptions.length - 1]}
			>
				<span class="material-symbols">chevron_right</span>
			</button>
			<button
				type="button"
				class="jumper-today"
				onclick={() => jumpToYear(today.getFullYear())}
			>
				Today
			</button>
		</div>

		<div class="dow-row" aria-hidden="true">
			{#each DOW_LABELS as dow, i (i)}
				<span>{dow}</span>
			{/each}
		</div>

		<div class="months" bind:this={monthsEl} onscroll={onMonthsScroll}>
			{#each Array.from({ length: monthCount }, (_, i) => i) as i (i)}
				{@const month = monthAt(i)}
				{@const firstOfMonth = new Date(month.getFullYear(), month.getMonth(), 1)}
				{@const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()}
				{@const leading = (firstOfMonth.getDay() + 6) % 7}
				<section class="month" data-month-idx={i}>
					<h3 class="month-name">
						{MONTH_NAMES[month.getMonth()]} {month.getFullYear()}
					</h3>
					<div class="grid">
						{#each Array.from({ length: leading }, (_, k) => k) as pad (pad)}
							<span class="cell empty"></span>
						{/each}
						{#each Array.from({ length: daysInMonth }, (_, d) => d + 1) as day (day)}
							{@const date = new Date(month.getFullYear(), month.getMonth(), day)}
							{@const isStart = pendingFrom !== null && sameDay(date, pendingFrom)}
							{@const isEnd = pendingTo !== null && sameDay(date, pendingTo)}
							{@const inRange =
								pendingFrom !== null &&
								pendingTo !== null &&
								date > pendingFrom &&
								date < pendingTo}
							{@const isToday = sameDay(date, today)}
							<button
								type="button"
								class="cell"
								class:start={isStart}
								class:end={isEnd}
								class:in-range={inRange}
								class:today={isToday && !isStart && !isEnd}
								onclick={() => onTapDate(date)}
								aria-label={formatChip(date)}
							>
								<span class="day">{day}</span>
							</button>
						{/each}
					</div>
				</section>
			{/each}
		</div>

		<footer class="actions">
			<button
				type="button"
				class="btn btn-outline"
				disabled={pendingFrom === null && pendingTo === null}
				onclick={clearPending}>Clear</button>
			<button
				type="button"
				class="btn btn-primary"
				disabled={!canApply}
				onclick={apply}>Apply</button>
		</footer>
	</div>
</Modal>

<style>
	.range-picker {
		display: flex;
		flex-direction: column;
		min-height: 0;
		max-height: min(72vh, 560px);
	}

	.chip-row {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 8px;
		padding: 0 0 8px;
	}

	.chip {
		display: flex;
		flex-direction: column;
		gap: 1px;
		padding: 6px 10px;
		border-radius: 8px;
		border: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.chip.active {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
	}

	.chip-label {
		font-size: 0.65rem;
		letter-spacing: 0.05em;
		font-weight: 600;
		color: var(--color-text-tertiary);
	}

	.chip-value {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text);
	}

	.jumper-row {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 0 0 8px;
	}
	.jumper-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		padding: 0;
		border: 1px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-text);
		border-radius: 6px;
		cursor: pointer;
	}
	.jumper-btn:hover:not(:disabled) {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.jumper-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.jumper-btn .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1.1rem;
	}
	.jumper-select {
		flex: 1;
		padding: 4px 8px;
		border: 1px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.9rem;
		font-weight: 600;
		border-radius: 6px;
		cursor: pointer;
		text-align: center;
	}
	.jumper-today {
		padding: 4px 10px;
		border: 1px solid var(--color-border);
		background: var(--color-surface);
		color: var(--color-text);
		font-size: 0.8rem;
		font-weight: 500;
		border-radius: 6px;
		cursor: pointer;
	}
	.jumper-today:hover {
		border-color: var(--color-primary);
		background: var(--color-primary-light);
	}

	.dow-row {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		padding: 4px 0;
		border-top: 1px solid var(--color-border);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
		position: sticky;
		top: 0;
		z-index: 1;
	}

	.dow-row span {
		text-align: center;
		font-size: 0.7rem;
		font-weight: 600;
		color: var(--color-text-secondary);
	}

	.months {
		flex: 1;
		min-height: 0;
		overflow-y: auto;
	}

	.month {
		padding: 6px 0 2px;
	}

	.month-name {
		font-size: 0.85rem;
		font-weight: 600;
		color: var(--color-text);
		margin: 0 0 4px;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
	}

	.cell {
		all: unset;
		height: 36px;
		display: flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		position: relative;
		font-size: 0.85rem;
		color: var(--color-text);
		transition: background-color 80ms ease;
	}

	.cell.empty {
		cursor: default;
	}

	.cell:not(.empty):hover {
		background: var(--color-primary-light);
	}

	.cell.in-range {
		background: var(--color-primary-light);
	}

	.cell.start,
	.cell.end {
		color: #fff;
	}

	.cell.start::before,
	.cell.end::before {
		content: '';
		position: absolute;
		inset: 3px;
		border-radius: 50%;
		background: var(--color-primary);
		z-index: 0;
	}

	.cell.start {
		background: linear-gradient(to right, transparent 50%, var(--color-primary-light) 50%);
	}
	.cell.end {
		background: linear-gradient(to right, var(--color-primary-light) 50%, transparent 50%);
	}
	.cell.start.end {
		background: transparent;
	}

	.cell.today::before {
		content: '';
		position: absolute;
		inset: 3px;
		border: 1.4px solid var(--color-primary);
		border-radius: 50%;
		z-index: 0;
	}

	.cell .day {
		position: relative;
		z-index: 1;
		font-weight: 500;
	}

	.cell.start .day,
	.cell.end .day {
		font-weight: 600;
	}

	.actions {
		display: flex;
		justify-content: space-between;
		gap: 8px;
		padding: 8px 0 0;
		border-top: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	:global(.range-body) {
		display: flex;
		flex-direction: column;
		min-height: 0;
		padding: 10px 12px;
	}
</style>
