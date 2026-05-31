<!--
	Route-direction scrubber for the route detail page. Drag the
	thumb from 0 → 100 % and a runner marker glides along the
	polyline so the user can preview the direction of the run
	before they start.

	Twin of `_RoutePreviewScrubber` in
	`apps/mobile_android/lib/screens/route_detail_screen.dart`. Both
	platforms share the same `interpolateAlongRoute` helper so the
	position the user sees is identical to the metre.

	Self-contained — owns no map state. Emits a 0..1 `fraction` via
	`onchange` plus a `scrubbing` flag via `onscrubbing` so the
	parent can mount the runner marker only while the thumb is
	actively dragged. The parent computes the interpolated lat/lng
	via `interpolateAlongRoute(waypoints, fraction)` and passes it
	to `RunMap`'s `previewLngLat` prop.
-->
<script lang="ts">
	import { formatDistance } from '$lib/format/units.svelte';
	interface Props {
		totalDistanceM: number;
		fraction: number;
		onchange: (fraction: number) => void;
		onscrubbing: (active: boolean) => void;
	}
	let { totalDistanceM, fraction, onchange, onscrubbing }: Props = $props();
</script>

<div class="scrubber">
	<div class="header">
		<span class="title">
			<span class="material-symbols">directions_run</span>
			Preview
		</span>
		<span class="reached" data-testid="scrubber-reached">
			{formatDistance(totalDistanceM * fraction)}
		</span>
	</div>
	<input
		type="range"
		min="0"
		max="1"
		step="0.001"
		value={fraction}
		data-testid="route-scrubber"
		oninput={(e) => {
			const v = parseFloat((e.target as HTMLInputElement).value);
			onchange(Math.min(1, Math.max(0, v)));
		}}
		onpointerdown={() => onscrubbing(true)}
		onpointerup={() => onscrubbing(false)}
		onpointercancel={() => onscrubbing(false)}
		onmousedown={() => onscrubbing(true)}
		onmouseup={() => onscrubbing(false)}
		ontouchstart={() => onscrubbing(true)}
		ontouchend={() => onscrubbing(false)}
		ontouchcancel={() => onscrubbing(false)}
		onfocus={() => onscrubbing(true)}
		onblur={() => onscrubbing(false)}
	/>
	<div class="ends">
		<span>Start</span>
		<span>Finish</span>
	</div>
</div>

<style>
	.scrubber {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 8px 0 4px;
	}
	.header {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 13px;
	}
	.title {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--text-muted, #6b7280);
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		font-size: 11px;
	}
	.reached {
		margin-left: auto;
		color: var(--text-muted, #6b7280);
	}
	input[type='range'] {
		width: 100%;
		accent-color: var(--accent, #4f46e5);
		cursor: pointer;
	}
	.ends {
		display: flex;
		justify-content: space-between;
		font-size: 11px;
		color: var(--text-muted, #6b7280);
		padding: 0 4px;
	}
</style>
