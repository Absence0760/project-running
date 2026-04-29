<script lang="ts">
	import { onMount } from 'svelte';
	import { fetchRunsOnRoute } from '$lib/data';
	import { formatDuration } from '$lib/mock-data';
	import {
		qualifyingAttempts,
		summariseHistory,
		formatSignedDelta,
		type RouteHistoryRun,
	} from '$lib/route_history';

	interface Props {
		currentRunId: string;
		routeId: string;
		distanceM: number;
		durationS: number;
		metadata: Record<string, unknown> | null;
		routeName?: string;
	}
	let {
		currentRunId,
		routeId,
		distanceM,
		durationS,
		metadata,
		routeName,
	}: Props = $props();

	let attempts = $state<RouteHistoryRun[]>([]);
	let loading = $state(true);

	onMount(async () => {
		const rows = await fetchRunsOnRoute(routeId);
		const me: RouteHistoryRun = {
			id: currentRunId,
			route_id: routeId,
			distance_m: distanceM,
			duration_s: durationS,
			metadata,
		};
		attempts = qualifyingAttempts(me, rows);
		loading = false;
	});

	let summary = $derived(summariseHistory(currentRunId, attempts));
</script>

{#if !loading && summary}
	<div class="route-history" class:is-pb={summary.isPb}>
		<div class="row">
			<span class="icon" aria-hidden="true">
				{summary.isPb ? '🏆' : '⏱'}
			</span>
			<span class="headline">
				{#if summary.isPb}
					Personal best on {routeName ?? 'this route'}
				{:else}
					{formatSignedDelta(summary.deltaSeconds)} behind PB
				{/if}
			</span>
		</div>
		<div class="meta">
			Attempt {summary.rank} of {summary.total} — PB:
			{formatDuration(summary.pb.duration_s)}
		</div>
	</div>
{/if}

<style>
	.route-history {
		padding: 1rem;
		border: 1px solid var(--color-border, #e5e5e5);
		border-radius: 0.5rem;
		background: var(--color-surface, #fff);
	}
	.route-history.is-pb {
		border-color: #eab308;
		background: rgba(234, 179, 8, 0.05);
	}
	.row {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-weight: 600;
	}
	.icon {
		font-size: 1.1rem;
	}
	.is-pb .headline {
		color: #b8860b;
	}
	.meta {
		margin-top: 0.25rem;
		color: var(--color-text-muted, #6b7280);
		font-size: 0.875rem;
	}
</style>
