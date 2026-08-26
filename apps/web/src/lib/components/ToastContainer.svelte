<script lang="ts">
	import { toastStore } from '$lib/stores/toast.svelte';

	// A live region only announces changes that happen INSIDE it while it is
	// already in the accessibility tree. The stack used to be mounted by an
	// `{#if}` alongside the toast, so region and text appeared in one mutation
	// and the first toast of a burst — the ordinary case, one toast at a time
	// across ~400 showToast call sites — was announced by nothing (WCAG 4.1.3).
	//
	// The two stacks are therefore permanent and only their CHILDREN change.
	// A separate visually-hidden mirror would work for a screen reader and put
	// the same sentence in the DOM twice, which makes every `getByText('…')`
	// toast assertion in the e2e suite a strict-mode violation — the announcer
	// and the visible toast are one element, not two.
	const errors = $derived(toastStore.toasts.filter((t) => t.type === 'error'));
	const others = $derived(toastStore.toasts.filter((t) => t.type !== 'error'));
</script>

<!--
	`aria-live` rather than role="status" / role="alert": the roles are
	shorthand for exactly these politeness values, and adding a permanent
	`alert` role to every page would make a bare getByRole('alert') ambiguous
	on surfaces that assert on their own inline error banner.

	`aria-atomic` is left at its default (false) because each stack holds a
	LIST: atomic would re-announce every toast still on screen each time one
	more arrives.
-->
<div class="toast-container">
	<div class="toast-stack" aria-live="polite" data-testid="toast-live-polite">
		{#each others as t (t.id)}
			<div class="toast toast-{t.type}">
				{t.message}
			</div>
		{/each}
	</div>
	<div class="toast-stack" aria-live="assertive" data-testid="toast-live-assertive">
		{#each errors as t (t.id)}
			<div class="toast toast-{t.type}">
				{t.message}
			</div>
		{/each}
	</div>
</div>

<style>
	.toast-container {
		position: fixed;
		bottom: var(--space-lg);
		inset-inline-end: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		z-index: var(--z-toast);
		max-width: 24rem;
		/* Permanently mounted now, so it sits over the page even with nothing in
		   it. An empty flex column has no box, but a toast must not eat a click
		   at the moment it appears either. */
		pointer-events: none;
	}
	.toast-stack {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.toast {
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		font-weight: 500;
		box-shadow: var(--shadow-lg);
		animation: slide-in 0.2s ease-out;
	}
	.toast-info {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		color: var(--color-text);
	}
	.toast-success {
		/* WCAG 2.2 AA: white on --color-success was 3.28:1 (light) /
		   2.22:1 (dark). --color-success-strong is 5.13:1. */
		background: var(--color-success-strong);
		color: white;
	}
	.toast-error {
		/* WCAG 2.2 AA: white on --color-danger was 3.06:1 in dark mode.
		   --color-danger-strong is 6.06:1 in both themes. */
		background: var(--color-danger-strong);
		color: white;
	}
	@keyframes slide-in {
		from { opacity: 0; transform: translateY(0.5rem); }
		to { opacity: 1; transform: translateY(0); }
	}
</style>
