<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import CoachChat from '$lib/components/CoachChat.svelte';
	import { fetchActivePlanOverview, fetchMyPlans } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
	import { GUIDED_RUN_LIBRARY } from '$lib/guided_runs';
	import type { TrainingPlan } from '$lib/types';

	let plans = $state<TrainingPlan[]>([]);
	let planId = $state<string | null>(null);
	let loaded = $state(false);

	// Read `?plan=<id>` from the URL on first load and whenever the param
	// changes (e.g. via the deep link from /plans/[id]). When absent, we
	// fall back to the user's active plan.
	let urlPlanParam = $derived($page.url.searchParams.get('plan'));

	onMount(async () => {
		// Wait for auth so the RLS-scoped fetches return the right rows.
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		try {
			plans = await fetchMyPlans();
		} catch (_) {
			plans = [];
		}
		await resolvePlanId();
		loaded = true;
	});

	$effect(() => {
		// Re-resolve when the query param changes (browser back/forward, or
		// the user picks a different plan in the switcher).
		if (loaded) resolvePlanId();
	});

	async function resolvePlanId() {
		const fromUrl = urlPlanParam;
		// Explicit "no plan" sentinel — user picked "No plan" in the
		// strip dropdown. Stay null; do NOT fall back to the active
		// plan or the user's first save reverts on the next load.
		if (fromUrl === 'none') {
			planId = null;
			return;
		}
		if (fromUrl && plans.some((p) => p.id === fromUrl)) {
			planId = fromUrl;
			return;
		}
		// No (or stale) query param — default to the user's active plan.
		try {
			const overview = await fetchActivePlanOverview();
			planId = overview?.plan.id ?? null;
		} catch (_) {
			planId = null;
		}
	}

	function pickPlan(next: string) {
		// Reflect the choice in the URL so refresh / share keeps the
		// context, and so $effect above re-runs `resolvePlanId`.
		// `next === ''` means the user picked the "No plan" option in
		// the strip dropdown; we encode that as `?plan=none` so a
		// reload re-reads the explicit choice instead of falling back
		// to the active plan.
		const params = new URLSearchParams($page.url.searchParams);
		if (next === '') params.set('plan', 'none');
		else params.set('plan', next);
		const qs = params.toString();
		goto(qs ? `/coach?${qs}` : '/coach', { replaceState: true, noScroll: true });
	}

	function fmtMinutes(seconds: number): string {
		const m = Math.round(seconds / 60);
		return `${m} min`;
	}
</script>

<svelte:head>
	<title>Coach — Run Onward</title>
</svelte:head>

<div class="page">
	<div class="chat-host">
		{#if loaded}
			{#key planId}
				<CoachChat {planId} {plans} onPlanChange={pickPlan} />
			{/key}
		{:else}
			<p class="muted">Loading…</p>
		{/if}
	</div>

	<aside class="guided" aria-labelledby="guided-heading">
		<header class="guided-head">
			<h2 id="guided-heading">Guided runs</h2>
			<p class="guided-sub">
				Coach-voice scripted workouts. Cues fire on the mobile app — this is the preview.
			</p>
		</header>
		<ul class="guided-list">
			{#each GUIDED_RUN_LIBRARY as g (g.id)}
				<li>
					<a class="guided-card" href="/guided/{g.id}">
						<div class="guided-card-head">
							<span class="duration">{fmtMinutes(g.duration_sec)}</span>
							<span class="cue-count">{g.cues.length} cues</span>
						</div>
						<h3>{g.title}</h3>
						<p class="guided-card-sub">{g.subtitle}</p>
					</a>
				</li>
			{/each}
		</ul>
		<a class="guided-all" href="/guided">
			<span class="material-symbols">arrow_forward</span>
			See the full library
		</a>
	</aside>
</div>

<style>
	.page {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 20rem;
		gap: var(--space-md);
		padding: var(--space-md) var(--space-lg);
		height: 100vh;
		min-height: 0;
	}
	.chat-host {
		display: flex;
		flex-direction: column;
		min-height: 0;
		min-width: 0;
	}
	/* The CoachChat wrapper renamed from `.chat` to `.shell` when the
	   sidebar landed; the global selector mirrors that. */
	.chat-host > :global(.shell) {
		height: 100%;
	}
	.muted {
		color: var(--color-text-tertiary);
	}

	/* Right rail — surfaces the Guided run library so it's reachable
	   from the coach surface without burning a top-level sidebar slot.
	   Coach + Guided are both coach-driven; sitting them side-by-side
	   makes the relationship visible. */
	.guided {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		overflow-y: auto;
		min-height: 0;
	}
	.guided-head h2 {
		font-size: 0.95rem;
		font-weight: 600;
		margin: 0 0 var(--space-2xs);
	}
	.guided-sub {
		font-size: 0.78rem;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-sm);
		line-height: 1.4;
	}
	.guided-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.guided-card {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		padding: var(--space-sm) var(--space-md);
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		text-decoration: none;
		color: inherit;
		transition:
			border-color var(--transition-fast),
			transform var(--transition-fast);
	}
	.guided-card:hover {
		border-color: var(--color-primary);
		transform: translateY(-1px);
	}
	.guided-card-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-sm);
	}
	.duration {
		background: color-mix(in srgb, var(--color-primary) 12%, transparent);
		color: var(--color-primary);
		padding: 0.1rem 0.5rem;
		border-radius: 999px;
		font-size: 0.7rem;
		font-weight: 700;
	}
	.cue-count {
		font-size: 0.72rem;
		color: var(--color-text-tertiary);
	}
	.guided-card h3 {
		margin: 0;
		font-size: 0.9rem;
		font-weight: 600;
		line-height: 1.3;
	}
	.guided-card-sub {
		font-size: 0.78rem;
		color: var(--color-text-secondary);
		margin: 0;
		line-height: 1.4;
	}
	.guided-all {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		margin-top: auto;
		padding: var(--space-xs) var(--space-sm);
		font-size: 0.82rem;
		font-weight: 500;
		color: var(--color-text-secondary);
		text-decoration: none;
		border-radius: var(--radius-md);
		transition: color var(--transition-fast), background var(--transition-fast);
	}
	.guided-all:hover {
		color: var(--color-primary);
		background: var(--color-bg-tertiary);
	}
	.guided-all .material-symbols {
		font-family: 'Material Symbols Outlined';
		font-size: 1rem;
	}

	/* Narrow viewports: stack the rail under the chat. The chat keeps
	   its full-height feel; the rail becomes a horizontally scrollable
	   strip below. */
	@media (max-width: 64rem) {
		.page {
			grid-template-columns: minmax(0, 1fr);
			grid-template-rows: minmax(0, 1fr) auto;
			height: auto;
			min-height: 100vh;
		}
		.chat-host {
			min-height: 36rem;
		}
		.guided-list {
			flex-direction: row;
			overflow-x: auto;
			padding-bottom: var(--space-xs);
		}
		.guided-list > li {
			flex: 0 0 16rem;
		}
		.guided-all {
			align-self: flex-start;
		}
	}
</style>
