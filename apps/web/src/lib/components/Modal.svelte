<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';

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
				return;
			}
			// Trap Tab inside the dialog while open: the page behind is
			// still in the DOM (no inert), so without this a keyboard user
			// tabs out of the last control straight into the obscured page.
			if (e.key !== 'Tab' || !dialogEl) return;
			const focusable = [
				...dialogEl.querySelectorAll<HTMLElement>(
					'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), ' +
						'select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
				),
			].filter((el) => el.getClientRects().length > 0);
			if (focusable.length === 0) {
				e.preventDefault();
				dialogEl.focus();
				return;
			}
			const first = focusable[0];
			const last = focusable[focusable.length - 1];
			const active = document.activeElement as HTMLElement | null;
			const inside = active != null && dialogEl.contains(active);
			if (e.shiftKey) {
				if (!inside || active === first || active === dialogEl) {
					e.preventDefault();
					last.focus();
				}
			} else if (!inside || active === last) {
				e.preventDefault();
				first.focus();
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
				aria-label={m('modal.close')}
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
