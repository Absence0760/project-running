<script lang="ts">
	import { onMount } from 'svelte';
	import { formatDuration } from '$lib/format/time';
	import { fetchRunsOnRoute } from '$lib/core/data';
	
	import {
		qualifyingAttempts,
		summariseHistory,
		formatSignedDelta,
		type RouteHistoryRun,
	} from '$lib/routes/route_history';

	interface Props {
		currentRunId: string;
		routeId: string;
		distanceM: number;
		durationS: number;
		activityType: string | null;
		routeName?: string;
	}
	let {
		currentRunId,
		routeId,
		distanceM,
		durationS,
		activityType,
		routeName,
	}: Props = $props();

	let attempts = $state<RouteHistoryRun[]>([]);
	let loading = $state(true);

	onMount(async () => {
		try {
			const rows = await fetchRunsOnRoute(routeId);
			const me: RouteHistoryRun = {
				id: currentRunId,
				route_id: routeId,
				distance_m: distanceM,
				duration_s: durationS,
				activity_type: activityType,
			};
			attempts = qualifyingAttempts(me, rows);
		} catch (e) {
			// Enhancement panel: on failure it self-hides (never renders a
			// wrong "past efforts" summary). Clearing loading in finally
			// avoids the stuck-loading + unhandled-rejection the no-catch
			// load had.
			console.warn('route history load failed', e);
		} finally {
			loading = false;
		}
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
