<script lang="ts">
	import { toastStore } from '$lib/stores/toast.svelte';
</script>

<!--
	audit/accessibility High (May 2026): the container had no
	aria-live region, so screen readers never announced "Run
	saved" / "Export failed" / etc. Wrap in role="status" +
	aria-live="polite" by default; per-toast aria-live="assertive"
	for error toasts so the user is interrupted on failure but not
	on routine confirmations.
-->
{#if toastStore.toasts.length > 0}
	<div class="toast-container" role="status" aria-live="polite" aria-atomic="false">
		{#each toastStore.toasts as t (t.id)}
			<div
				class="toast toast-{t.type}"
				role={t.type === 'error' ? 'alert' : 'status'}
				aria-live={t.type === 'error' ? 'assertive' : 'polite'}
			>
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
