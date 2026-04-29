<script lang="ts">
	import { onMount } from 'svelte';
	import type { Snippet } from 'svelte';

	interface Props {
		storageKey: string;
		min?: number;
		max?: number;
		initialFraction?: number;
		left: Snippet;
		right: Snippet;
	}

	let {
		storageKey,
		min = 280,
		max,
		initialFraction = 0.6,
		left,
		right,
	}: Props = $props();

	let containerEl: HTMLDivElement;
	let leftPx = $state<number | null>(null);
	let dragging = $state(false);

	onMount(() => {
		let initial: number | null = null;
		try {
			const v = localStorage.getItem(storageKey);
			if (v) {
				const n = parseInt(v, 10);
				if (Number.isFinite(n) && n > 0) initial = n;
			}
		} catch (_) {
			/* localStorage may be unavailable */
		}
		if (initial == null) {
			const w = containerEl?.clientWidth ?? 0;
			initial = Math.round(w * initialFraction);
		}
		leftPx = clamp(initial);
	});

	function clamp(v: number) {
		const w = containerEl?.clientWidth ?? 0;
		// Reserve `min` for the right pane too so the panel can never be dragged into nothing.
		const upper = Math.max(min, Math.min(max ?? Infinity, w - min));
		return Math.max(min, Math.min(upper, v));
	}

	function persist() {
		try {
			if (leftPx != null) localStorage.setItem(storageKey, String(leftPx));
		} catch (_) {
			/* silent */
		}
	}

	function startDrag(e: PointerEvent) {
		if (!containerEl) return;
		e.preventDefault();
		dragging = true;
		document.body.style.cursor = 'col-resize';
		document.body.style.userSelect = 'none';
		const onMove = (ev: PointerEvent) => {
			if (!containerEl) return;
			const rect = containerEl.getBoundingClientRect();
			leftPx = clamp(ev.clientX - rect.left);
		};
		const onUp = () => {
			dragging = false;
			document.body.style.cursor = '';
			document.body.style.userSelect = '';
			window.removeEventListener('pointermove', onMove);
			window.removeEventListener('pointerup', onUp);
			persist();
		};
		window.addEventListener('pointermove', onMove);
		window.addEventListener('pointerup', onUp);
	}

	function onKey(e: KeyboardEvent) {
		if (leftPx == null) return;
		const step = e.shiftKey ? 32 : 8;
		if (e.key === 'ArrowLeft') {
			leftPx = clamp(leftPx - step);
			e.preventDefault();
		} else if (e.key === 'ArrowRight') {
			leftPx = clamp(leftPx + step);
			e.preventDefault();
		} else {
			return;
		}
		persist();
	}
</script>

<div class="split-pane" bind:this={containerEl}>
	<div
		class="split-left"
		style:width={leftPx != null ? `${leftPx}px` : `${initialFraction * 100}%`}
	>
		{@render left()}
	</div>
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions a focusable splitter separator is interactive even though Svelte's lint can't tell -->
	<div
		class="split-divider"
		class:dragging
		role="separator"
		aria-orientation="vertical"
		aria-label="Drag to resize panes"
		tabindex="0"
		onpointerdown={startDrag}
		onkeydown={onKey}
	></div>
	<div class="split-right">
		{@render right()}
	</div>
</div>

<style>
	.split-pane {
		display: flex;
		flex: 1;
		min-height: 0;
		width: 100%;
		height: 100%;
	}

	.split-left {
		height: 100%;
		flex-shrink: 0;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}

	.split-right {
		flex: 1;
		height: 100%;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}

	.split-divider {
		flex: 0 0 6px;
		cursor: col-resize;
		background: var(--color-border);
		position: relative;
		transition: background var(--transition-fast);
		touch-action: none;
	}

	/* Wider hit area than visible border so users don't have to be pixel-perfect. */
	.split-divider::before {
		content: '';
		position: absolute;
		top: 0;
		bottom: 0;
		left: -4px;
		right: -4px;
	}

	.split-divider:hover,
	.split-divider:focus-visible,
	.split-divider.dragging {
		background: var(--color-primary);
		outline: none;
	}
</style>
