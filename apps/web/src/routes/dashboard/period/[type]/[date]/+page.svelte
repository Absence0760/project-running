<script lang="ts">
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { fetchRuns } from '$lib/data';
	import { formatISO } from '$lib/training';
	import PeriodSummary from '$lib/components/PeriodSummary.svelte';
	import type { Run } from '$lib/types';

	type PeriodType = 'week' | 'month';

	let type = $derived<PeriodType>(
		$page.params.type === 'month' ? 'month' : 'week',
	);
	let initialDate = $derived<Date>(parsePeriodDate($page.params.date ?? ''));

	let runs = $state<Run[]>([]);
	let loading = $state(true);

	onMount(async () => {
		runs = await fetchRuns();
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
	{#if loading}
		<p class="loading">Loading…</p>
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
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 72rem; }
	.loading { color: var(--color-text-tertiary); }
</style>
