<script lang="ts">
	import { toastStore } from '$lib/stores/toast.svelte';
</script>

{#if toastStore.toasts.length > 0}
	<div class="toast-container">
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
		bottom: 1.5rem;
		right: 1.5rem;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		z-index: 300;
		max-width: 24rem;
	}
	.toast {
		padding: 0.7rem 1.2rem;
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		font-weight: 500;
		box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2);
		animation: slide-in 0.2s ease-out;
	}
	.toast-info {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		color: var(--color-text);
	}
	.toast-success {
		background: #2e7d32;
		color: white;
	}
	.toast-error {
		background: var(--color-danger);
		color: white;
	}
	@keyframes slide-in {
		from { opacity: 0; transform: translateY(0.5rem); }
		to { opacity: 1; transform: translateY(0); }
	}
</style>
