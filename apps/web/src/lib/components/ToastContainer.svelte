<script lang="ts">
	import { toastStore } from '$lib/stores/toast.svelte';

	// A live region only announces changes that happen INSIDE it while it is
	// already in the accessibility tree. The region used to be mounted by the
	// same `{#if}` that mounted the toast, so region and text appeared in one
	// mutation and the first toast of a burst — the ordinary case, one toast at
	// a time — was announced by nothing. Both regions are therefore permanent
	// and only their text changes, the idiom CoachChat's announcer already uses.
	// The visible stack is aria-hidden so a toast is never spoken twice.
	const errors = $derived(toastStore.toasts.filter((t) => t.type === 'error'));
	const others = $derived(toastStore.toasts.filter((t) => t.type !== 'error'));
	const assertiveText = $derived(errors.at(-1)?.message ?? '');
	const politeText = $derived(others.at(-1)?.message ?? '');
</script>

<!--
	`aria-live` rather than role="status" / role="alert": the roles are
	shorthand for exactly these politeness values, and adding a permanent
	`alert` role to every page would make a bare getByRole('alert') ambiguous
	on surfaces that assert on their own inline error banner.
-->
<div class="visually-hidden" aria-live="polite" aria-atomic="true" data-testid="toast-live-polite">
	{politeText}
</div>
<div
	class="visually-hidden"
	aria-live="assertive"
	aria-atomic="true"
	data-testid="toast-live-assertive"
>
	{assertiveText}
</div>

{#if toastStore.toasts.length > 0}
	<div class="toast-container" aria-hidden="true">
		{#each toastStore.toasts as t (t.id)}
			<div class="toast toast-{t.type}">
				{t.message}
			</div>
		{/each}
	</div>
{/if}

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
