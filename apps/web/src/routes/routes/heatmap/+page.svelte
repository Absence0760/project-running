<script lang="ts">
	/// Standalone heatmap page. Extracted from `/routes?tab=heatmap`
	/// in the May 2026 audit pass because the tab-parent's flex
	/// chain (page-header → page-heatmap → heatmap-wrap → map)
	/// interacted badly with MapLibre's canvas allocation timing —
	/// the map's `getBoundingClientRect.y` reported -345 in the
	/// debug pass, the visible map rendered at ~80 px tall, and
	/// any popup that projected to the map's centre landed far
	/// below the visible canvas.
	///
	/// At this dedicated route the heatmap owns the layout column
	/// outright: `position: fixed` against the viewport (with
	/// sidebar inset), no flex chain, no page-header above. The
	/// RouteHeatmap component's resize observer + MapLibre's
	/// canvas sizing converge to the same dimensions immediately.
	///
	/// The `/routes?tab=heatmap` URL still works — the tab switcher
	/// in `/routes/+page.svelte` redirects there client-side so
	/// pre-existing deep links keep functioning.
	import RouteHeatmap from '$lib/components/RouteHeatmap.svelte';
	import { m } from '$lib/i18n/store.svelte';
</script>

<svelte:head>
	<title>{m('routesHeatmapPage.documentTitle')}</title>
</svelte:head>

<div class="heatmap-root">
	<RouteHeatmap />
</div>

<style>
	/*
	 * Position fixed against the viewport, inset from the sidebar
	 * column. No flex chain to interact with — RouteHeatmap gets a
	 * concrete container size from the moment its `<div bind:this=
	 * {mapEl}>` first paints, which is what MapLibre needs to
	 * allocate the WebGL canvas at the final size.
	 *
	 * The sidebar width is a CSS custom property from the app
	 * shell (see `+layout.svelte`). Using the custom property
	 * keeps this in sync if the sidebar collapses.
	 */
	.heatmap-root {
		position: fixed;
		top: 0;
		bottom: 0;
		inset-inline-start: var(--sidebar-width, 0);
		inset-inline-end: 0;
		overflow: hidden;
		/* Layout column transition mirror so the heatmap re-flows
		 * smoothly when the user collapses/expands the sidebar. */
		transition: left var(--transition-base);
	}
	/* Match the sidebar-collapsed offset so we don't lag behind. */
	:global(.app-shell.sidebar-collapsed) .heatmap-root {
		inset-inline-start: var(--sidebar-collapsed-width, 4.5rem);
	}
</style>
