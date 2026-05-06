<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import CoachChat from '$lib/components/CoachChat.svelte';
	import { fetchActivePlanOverview, fetchMyPlans } from '$lib/data';
	import { auth } from '$lib/stores/auth.svelte';
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
		if (fromUrl && plans.some((p) => p.id === fromUrl)) {
			planId = fromUrl;
			return;
		}
		// No valid query param — pick the active plan if there is one.
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
		const params = new URLSearchParams($page.url.searchParams);
		if (next === '') params.delete('plan');
		else params.set('plan', next);
		const qs = params.toString();
		goto(qs ? `/coach?${qs}` : '/coach', { replaceState: true, noScroll: true });
	}

	let activePlan = $derived(plans.find((p) => p.id === planId) ?? null);
</script>

<div class="page">
	{#if plans.length > 1}
		<header class="page-header">
			<label class="plan-picker">
				<span class="visually-hidden">Plan</span>
				<select
					value={planId ?? ''}
					onchange={(e) => pickPlan((e.currentTarget as HTMLSelectElement).value)}
				>
					<option value="">No plan (recent runs only)</option>
					{#each plans as p}
						<option value={p.id}>
							{p.name}{p.status === 'active' ? ' · active' : p.status === 'completed' ? ' · done' : ''}
						</option>
					{/each}
				</select>
			</label>
		</header>
	{/if}

	<div class="chat-host">
		{#if loaded}
			{#key planId}
				<CoachChat {planId} />
			{/key}
		{:else}
			<p class="muted">Loading…</p>
		{/if}
	</div>
</div>

<style>
	.page {
		padding: var(--space-md) var(--space-lg);
		display: flex;
		flex-direction: column;
		height: 100vh;
	}
	.page-header {
		margin-bottom: var(--space-sm);
		flex-shrink: 0;
		display: flex;
		justify-content: flex-end;
	}
	.chat-host {
		flex: 1;
		min-height: 0;
		display: flex;
		flex-direction: column;
	}
	/* The CoachChat wrapper renamed from `.chat` to `.shell` when the
	   sidebar landed; the global selector mirrors that. */
	.chat-host > :global(.shell) {
		height: 100%;
	}
	.plan-picker select {
		background: var(--color-bg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.4rem 0.7rem;
		font: inherit;
		color: inherit;
		font-size: 0.85rem;
		max-width: 18rem;
	}
	.plan-picker select:focus {
		outline: none;
		border-color: var(--color-primary);
	}
	.muted {
		color: var(--color-text-tertiary);
	}
	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
	}
</style>
