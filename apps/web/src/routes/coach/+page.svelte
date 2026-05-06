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
</script>

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
</div>

<style>
	.page {
		padding: var(--space-md) var(--space-lg);
		display: flex;
		flex-direction: column;
		height: 100vh;
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
	.muted {
		color: var(--color-text-tertiary);
	}
</style>
