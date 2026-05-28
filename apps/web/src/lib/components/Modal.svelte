<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		open: boolean;
		onclose: () => void;
		title: string;
		wide?: boolean;
		narrow?: boolean;
		bodyClass?: string;
		/// When false, the backdrop is fully transparent — outside-
		/// click-to-close still works, but the page underneath isn't
		/// darkened. Useful for lightweight pickers (e.g. the date-
		/// range picker on /runs) where the page-dim feels heavier
		/// than the action warrants.
		dimBackdrop?: boolean;
		children: Snippet;
		/// Forwarded to the rendered dialog element so e2e specs
		/// can target a specific modal on a page that hosts more
		/// than one (e.g. ConfirmDialog wraps Modal + adds its own
		/// data-testid; consumers pass it through).
		'data-testid'?: string;
	}

	let {
		open,
		onclose,
		title,
		wide = false,
		narrow = false,
		bodyClass = '',
		dimBackdrop = true,
		children,
		'data-testid': testId,
	}: Props = $props();

	let dialogEl = $state<HTMLDivElement | null>(null);
	let prevFocus: HTMLElement | null = null;

	$effect(() => {
		if (!open) return;
		// Save focus + lock body scroll while open. Restore both on close.
		prevFocus = document.activeElement as HTMLElement | null;
		const prevOverflow = document.body.style.overflow;
		document.body.style.overflow = 'hidden';

		const onKey = (e: KeyboardEvent) => {
			if (e.key === 'Escape') {
				e.stopPropagation();
				onclose();
			}
		};
		window.addEventListener('keydown', onKey);

		// Move focus into the dialog on open so screen readers announce it
		// and Escape works without first-clicking somewhere inside.
		queueMicrotask(() => dialogEl?.focus());

		return () => {
			window.removeEventListener('keydown', onKey);
			document.body.style.overflow = prevOverflow;
			if (prevFocus && document.body.contains(prevFocus)) prevFocus.focus();
		};
	});
</script>

{#if open}
	<div
		class="modal-backdrop"
		class:transparent={!dimBackdrop}
		onclick={onclose}
		role="presentation"
	></div>
	<div
		class="modal"
		class:modal-wide={wide}
		class:modal-narrow={narrow}
		role="dialog"
		aria-modal="true"
		aria-label={title}
		bind:this={dialogEl}
		tabindex="-1"
		data-testid={testId}
	>
		<header class="modal-header">
			<h2>{title}</h2>
			<button
				class="modal-close"
				type="button"
				aria-label="Close"
				onclick={onclose}
			>
				<span class="material-symbols">close</span>
			</button>
		</header>
		<div class="modal-body {bodyClass}">
			{@render children()}
		</div>
	</div>
{/if}
