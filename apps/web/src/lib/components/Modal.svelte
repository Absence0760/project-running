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

	const FOCUSABLE =
		'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), ' +
		'select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

	function focusablesIn(root: ParentNode): HTMLElement[] {
		return [...root.querySelectorAll<HTMLElement>(FOCUSABLE)].filter(
			(el) => el.getClientRects().length > 0,
		);
	}

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
			const dlg = dialogEl;
			const dialogRing = focusablesIn(dlg);
			// An element marked `data-modal-trap-include` joins the ring even
			// though it sits outside the dialog. It exists for a transient
			// global affordance a modal action PRODUCES — the undo bar — which
			// the trap would otherwise make mouse-only. It joins at the END:
			// the offer is a consequence of what the user just did in the
			// dialog, so that is where it reads (WCAG 2.4.3), independent of
			// where in the layout the host happens to be mounted. Nothing
			// pending means no focusables, so the ring is bit-for-bit the
			// dialog's own.
			const outerRing = [
				...document.querySelectorAll<HTMLElement>('[data-modal-trap-include]'),
			]
				.filter((host) => !dlg.contains(host))
				.flatMap(focusablesIn);
			const ring = [...dialogRing, ...outerRing];
			if (ring.length === 0) {
				e.preventDefault();
				dlg.focus();
				return;
			}
			const first = ring[0];
			const last = ring[ring.length - 1];
			const dialogLast = dialogRing[dialogRing.length - 1];
			const active = document.activeElement as HTMLElement | null;
			const offRing = active == null || ring.indexOf(active) < 0;
			const hop = e.shiftKey
				? offRing || active === first
					? last
					: active === outerRing[0]
						? dialogLast
						: null
				: offRing
					? first
					: active === last
						? first
						: active === dialogLast
							? outerRing[0]
							: null;
			if (hop) {
				e.preventDefault();
				hop.focus();
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
