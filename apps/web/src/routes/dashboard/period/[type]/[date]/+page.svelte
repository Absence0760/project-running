<script lang="ts">
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { fetchRuns } from '$lib/data';
	import {
		formatDistance,
		formatDuration,
		formatPace,
		formatDate,
		sourceLabel,
		sourceColor,
	} from '$lib/mock-data';
	import { showToast } from '$lib/stores/toast.svelte';
	import type { Run } from '$lib/types';

	type PeriodType = 'week' | 'month';

	// Route params. `type` is 'week' | 'month'; `date` is the ISO date
	// of the period's starting Monday (week) or first of the month
	// (month). Anything else falls back to "this week" so a malformed
	// URL still renders something.
	let type = $derived<PeriodType>(
		$page.params.type === 'month' ? 'month' : 'week',
	);
	let startDate = $derived<Date>(parsePeriodDate($page.params.date ?? '', type));

	let runs = $state<Run[]>([]);
	let loading = $state(true);

	onMount(async () => {
		runs = await fetchRuns();
		loading = false;
	});

	function parsePeriodDate(raw: string, t: PeriodType): Date {
		const parsed = new Date(raw);
		if (!Number.isFinite(parsed.getTime())) {
			// Fallback: current period start.
			return periodStart(new Date(), t);
		}
		return periodStart(parsed, t);
	}

	function periodStart(d: Date, t: PeriodType): Date {
		const out = new Date(d);
		out.setHours(0, 0, 0, 0);
		if (t === 'week') {
			const dow = (out.getDay() + 6) % 7; // 0 = Mon
			out.setDate(out.getDate() - dow);
		} else {
			out.setDate(1);
		}
		return out;
	}

	function periodEnd(d: Date, t: PeriodType): Date {
		const out = new Date(d);
		if (t === 'week') {
			out.setDate(out.getDate() + 6);
			out.setHours(23, 59, 59, 999);
		} else {
			out.setMonth(out.getMonth() + 1);
			out.setDate(0);
			out.setHours(23, 59, 59, 999);
		}
		return out;
	}

	function shiftPeriod(dir: -1 | 1) {
		const next = new Date(startDate);
		if (type === 'week') next.setDate(next.getDate() + 7 * dir);
		else next.setMonth(next.getMonth() + dir);
		const iso = next.toISOString().slice(0, 10);
		goto(`/dashboard/period/${type}/${iso}`);
	}

	function periodLabel(d: Date, t: PeriodType): string {
		if (t === 'week') {
			const end = periodEnd(d, t);
			return `${d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })} – ${end.toLocaleDateString(
				undefined,
				{ month: 'short', day: 'numeric', year: 'numeric' },
			)}`;
		}
		return d.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
	}

	let periodRuns = $derived.by(() => {
		const start = startDate.getTime();
		const end = periodEnd(startDate, type).getTime();
		return runs.filter((r) => {
			const t = new Date(r.started_at).getTime();
			return t >= start && t <= end;
		});
	});

	let stats = $derived.by(() => {
		const d = periodRuns.reduce((s, r) => s + r.distance_m, 0);
		const t = periodRuns.reduce((s, r) => s + r.duration_s, 0);
		const longest = periodRuns.length
			? Math.max(...periodRuns.map((r) => r.distance_m))
			: 0;
		return { distance: d, duration: t, count: periodRuns.length, longest };
	});

	async function handleShare() {
		const lines = [
			`${type === 'week' ? 'Week of' : ''} ${periodLabel(startDate, type)}`,
			`Distance: ${formatDistance(stats.distance)}`,
			`Time: ${formatDuration(stats.duration)}`,
			`Runs: ${stats.count}`,
		];
		if (stats.count > 0) {
			lines.push(`Longest: ${formatDistance(stats.longest)}`);
			lines.push(
				`Avg pace: ${formatPace(stats.duration, stats.distance)} /km`,
			);
		}
		const text = lines.join('\n');
		try {
			if (navigator.share) {
				await navigator.share({ title: 'My running period', text });
			} else {
				await navigator.clipboard.writeText(text);
				showToast('Copied to clipboard.', 'success');
			}
		} catch (_) {
			/* user cancelled share — noop */
		}
	}
</script>

<div class="page">
	<header class="page-header">
		<div class="nav-row">
			<button class="nav-btn" onclick={() => shiftPeriod(-1)} type="button">
				<span class="material-symbols">chevron_left</span>
				Previous
			</button>
			<div class="center-labels">
				<div class="type-toggle">
					<button
						class="toggle-btn"
						class:active={type === 'week'}
						onclick={() =>
							goto(
								`/dashboard/period/week/${periodStart(startDate, 'week')
									.toISOString()
									.slice(0, 10)}`,
							)}
					>Week</button>
					<button
						class="toggle-btn"
						class:active={type === 'month'}
						onclick={() =>
							goto(
								`/dashboard/period/month/${periodStart(startDate, 'month')
									.toISOString()
									.slice(0, 10)}`,
							)}
					>Month</button>
				</div>
				<h1>{periodLabel(startDate, type)}</h1>
			</div>
			<button class="nav-btn" onclick={() => shiftPeriod(1)} type="button">
				Next
				<span class="material-symbols">chevron_right</span>
			</button>
		</div>
	</header>

	{#if loading}
		<p class="loading">Loading…</p>
	{:else}
		<div class="stats">
			<div class="stat-card">
				<span class="stat-label">Distance</span>
				<span class="stat-value">{formatDistance(stats.distance)}</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">Time</span>
				<span class="stat-value">{formatDuration(stats.duration)}</span>
			</div>
			<div class="stat-card">
				<span class="stat-label">Runs</span>
				<span class="stat-value">{stats.count}</span>
			</div>
			{#if stats.count > 0}
				<div class="stat-card">
					<span class="stat-label">Longest</span>
					<span class="stat-value">{formatDistance(stats.longest)}</span>
				</div>
			{/if}
		</div>

		<div class="actions">
			<button class="btn-secondary" onclick={handleShare} type="button">
				<span class="material-symbols">share</span>
				Share summary
			</button>
		</div>

		<section class="card">
			<h2>Runs in this {type}</h2>
			{#if periodRuns.length === 0}
				<p class="muted">No runs yet.</p>
			{:else}
				<div class="run-list">
					{#each periodRuns as run}
						<a href="/runs/{run.id}" class="run-row">
							<span class="run-date">{formatDate(run.started_at)}</span>
							<span
								class="source-badge"
								style="background: {sourceColor(run.source)}"
								>{sourceLabel(run.source)}</span
							>
							<span class="run-dist">{formatDistance(run.distance_m)}</span>
							<span class="run-time">{formatDuration(run.duration_s)}</span>
							<span class="run-pace"
								>{formatPace(run.duration_s, run.distance_m)} /km</span
							>
						</a>
					{/each}
				</div>
			{/if}
		</section>
	{/if}
</div>

<style>
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 56rem; }
	.nav-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}
	.center-labels { text-align: center; display: grid; gap: 0.5rem; }
	.nav-btn {
		display: inline-flex;
		align-items: center;
		gap: 0.25rem;
		padding: 0.4rem 0.8rem;
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.nav-btn:hover { color: var(--color-primary); border-color: var(--color-primary); }
	.type-toggle {
		display: inline-flex;
		gap: 0.25rem;
		background: var(--color-bg-tertiary);
		padding: 0.2rem;
		border-radius: var(--radius-md);
	}
	.toggle-btn {
		border: none;
		background: transparent;
		padding: 0.3rem 0.9rem;
		font-size: 0.82rem;
		border-radius: var(--radius-sm);
		cursor: pointer;
		color: var(--color-text-secondary);
	}
	.toggle-btn.active {
		background: var(--color-surface);
		color: var(--color-primary);
		font-weight: 600;
	}
	h1 {
		font-size: 1.4rem;
		font-weight: 800;
		margin: 0;
	}
	.stats {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-md);
		margin: var(--space-xl) 0;
	}
	@media (max-width: 40rem) {
		.stats { grid-template-columns: repeat(2, 1fr); }
	}
	.stat-card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1rem 1.25rem;
		display: flex;
		flex-direction: column;
	}
	.stat-label {
		font-size: 0.75rem;
		font-weight: 700;
		color: var(--color-text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	.stat-value {
		font-size: 1.5rem;
		font-weight: 800;
		margin-top: 0.3rem;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		margin-bottom: var(--space-lg);
	}
	.btn-secondary {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.5rem 1rem;
		background: transparent;
		border: 1px solid var(--color-primary);
		color: var(--color-primary);
		border-radius: var(--radius-md);
		font-size: 0.88rem;
		font-weight: 600;
		cursor: pointer;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.25rem 1.5rem;
	}
	.card h2 {
		font-size: 1rem;
		font-weight: 700;
		margin: 0 0 0.8rem;
	}
	.run-list { display: grid; gap: 0.4rem; }
	.run-row {
		display: grid;
		grid-template-columns: 1.2fr 0.6fr 0.8fr 0.8fr 0.8fr;
		gap: 0.6rem;
		padding: 0.55rem 0.75rem;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-md);
		text-decoration: none;
		color: inherit;
		font-size: 0.88rem;
	}
	.run-row:hover { background: color-mix(in srgb, var(--color-primary) 8%, var(--color-bg-tertiary)); }
	.source-badge {
		display: inline-block;
		padding: 0.1rem 0.4rem;
		border-radius: var(--radius-sm);
		color: white;
		font-size: 0.7rem;
		font-weight: 600;
		align-self: center;
		text-align: center;
	}
	.muted { color: var(--color-text-tertiary); margin: 0; }
	.loading { color: var(--color-text-tertiary); }
	.material-symbols { font-family: 'Material Symbols Outlined'; }
</style>
