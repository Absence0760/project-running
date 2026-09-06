<script lang="ts">
	import { page } from '$app/stores';
	import { afterNavigate, goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { fetchRunsForPeriodSummary, type PeriodSummaryRun } from '$lib/core/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { formatISO } from '$lib/training/training';
	import { m } from '$lib/i18n/store.svelte';
	import PeriodSummary from '$lib/components/PeriodSummary.svelte';
	import type { Run } from '$lib/types';

	type PeriodType = 'week' | 'month' | 'all';

	let type = $derived<PeriodType>(
		$page.params.type === 'month'
			? 'month'
			: $page.params.type === 'all'
				? 'all'
				: 'week',
	);
	let initialDate = $derived<Date>(parsePeriodDate($page.params.date ?? ''));

	// Resolve the heading copy in the script rather than inline in the
	// markup. A text-expression tag whose body starts with the bare
	// identifier `type` (`{type === ...}`) is misparsed as a declaration
	// tag by the Svelte 5.56.0 compiler ("Declaration tags must be `let`
	// or `const`"), which broke the production build. Deriving here keeps
	// the template free of that trigger.
	let kicker = $derived(
		type === 'week'
			? m('period.kickerWeek')
			: type === 'month'
				? m('period.kickerMonth')
				: m('period.kickerAll'),
	);
	let tagline = $derived(
		type === 'week'
			? m('period.taglineWeek')
			: type === 'month'
				? m('period.taglineMonth')
				: m('period.taglineAll'),
	);

	let runs = $state<PeriodSummaryRun[]>([]);
	let loading = $state(true);
	let loadFailed = $state(false);

	let cameFromDashboard = $state(false);
	afterNavigate(({ from }) => {
		if (!cameFromDashboard && from?.url.pathname === '/dashboard') {
			cameFromDashboard = true;
		}
	});
	function handleBack(e: MouseEvent): void {
		if (cameFromDashboard) {
			e.preventDefault();
			history.back();
		}
	}

	onMount(async () => {
		// Wait for the auth store to hydrate before the user-scoped fetch —
		// on a cold load (this page is built to be bookmarked / shared, per
		// the tagline) auth.user.id is null on first paint, so the fetch
		// would return [] and every period stat would render "—". Same
		// pattern the dashboard / coach / plans routes use (auth_ready.ts).
		await auth.ready();
		try {
			runs = await fetchRunsForPeriodSummary();
		} catch (_) {
			loadFailed = true;
		}
		loading = false;
	});

	function parsePeriodDate(raw: string): Date {
		const parsed = new Date(raw);
		return Number.isFinite(parsed.getTime()) ? parsed : new Date();
	}

	function handlePeriodChange(t: PeriodType, d: Date) {
		goto(`/dashboard/period/${t}/${formatISO(d)}`, { replaceState: true });
	}
</script>

<div class="page">
	<a class="back" href="/dashboard" onclick={handleBack}>
		<span class="material-symbols" aria-hidden="true">arrow_back</span>
		{m('period.back')}
	</a>

	<header class="page-header">
		<span class="kicker">{kicker}</span>
		<h1>{m('period.heading')}</h1>
		<p class="tagline">{tagline}</p>
	</header>

	{#if loading}
		<div class="skel-card" aria-hidden="true">
			<div class="skel-row">
				<span class="skel skel-line skel-w-20"></span>
				<span class="skel skel-line skel-w-30"></span>
			</div>
			<span class="skel skel-block"></span>
			<span class="skel skel-block"></span>
			<span class="skel skel-block"></span>
		</div>
		<p class="sr-only" role="status">{m('period.loading')}</p>
	{:else if loadFailed}
		<p class="load-error" role="alert">{m('periodSummary.historyFailed')}</p>
	{:else}
		<PeriodSummary
			{runs}
			initialType={type}
			{initialDate}
			onPeriodChange={handlePeriodChange}
		/>
	{/if}
</div>

<style>
	.page { padding: var(--page-padding-y) var(--page-padding-x); }

	.load-error { margin: 0; color: var(--color-danger-text); }

	.back {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		color: var(--color-text-secondary);
		font-size: 0.9rem;
		margin-bottom: var(--space-md);
		text-decoration: none;
	}
	.back:hover { color: var(--color-primary); }
	.back .material-symbols { font-size: 1.05rem; }

	.page-header {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		margin-bottom: var(--space-lg);
	}
	.kicker {
		font-size: var(--font-size-section-label);
		letter-spacing: 0.1em;
		color: var(--color-primary);
		font-weight: 700;
		text-transform: uppercase;
	}
	.page-header h1 {
		font-size: 1.75rem;
		font-weight: 700;
		line-height: 1.15;
		margin: 0;
	}
	.tagline {
		color: var(--color-text-secondary);
		font-size: 0.95rem;
		line-height: 1.5;
		max-width: 44rem;
		margin: var(--space-2xs) 0 0 0;
	}

	.skel-card {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		padding: var(--space-md);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
	}
	.skel-row {
		display: flex;
		justify-content: space-between;
	}
	.skel {
		display: block;
		background: var(--color-bg-tertiary);
		background-image: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 0%,
			var(--color-bg-secondary) 50%,
			var(--color-bg-tertiary) 100%
		);
		background-size: 200% 100%;
		border-radius: var(--radius-sm);
		animation: skel-shimmer 1.4s ease-in-out infinite;
	}
	.skel-line { height: 0.85rem; }
	.skel-block { height: 2.6rem; border-radius: var(--radius-md); }
	.skel-w-20 { width: 20%; }
	.skel-w-30 { width: 30%; }
	@keyframes skel-shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
	}

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}
</style>
