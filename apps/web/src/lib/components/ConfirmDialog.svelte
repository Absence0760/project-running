<script lang="ts">
	interface Props {
		open: boolean;
		title: string;
		message: string;
		confirmLabel?: string;
		cancelLabel?: string;
		danger?: boolean;
		onconfirm: () => void;
		oncancel: () => void;
	}

	let {
		open,
		title,
		message,
		confirmLabel = 'Confirm',
		cancelLabel = 'Cancel',
		danger = false,
		onconfirm,
		oncancel,
	}: Props = $props();
</script>

{#if open}
	<div class="backdrop" onclick={oncancel} role="presentation"></div>
	<div class="dialog" role="alertdialog" aria-label={title}>
		<h3>{title}</h3>
		<p>{message}</p>
		<div class="actions">
			<button class="btn cancel" onclick={oncancel}>{cancelLabel}</button>
			<button class="btn confirm" class:danger onclick={onconfirm}>{confirmLabel}</button>
		</div>
	</div>
{/if}

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.35);
		z-index: 200;
	}
	.dialog {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: 1.5rem;
		min-width: 20rem;
		max-width: 28rem;
		z-index: 201;
		box-shadow: 0 16px 40px rgba(0, 0, 0, 0.3);
	}
	h3 {
		font-size: 1rem;
		font-weight: 700;
		margin: 0 0 0.5rem;
	}
	p {
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		margin: 0 0 1.25rem;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
	.cancel {
		background: var(--color-bg-tertiary);
		color: var(--color-text);
	}
	.cancel:hover {
		background: var(--color-border);
	}
	.confirm {
		background: var(--color-primary);
		color: white;
	}
	.confirm:hover {
		background: var(--color-primary-hover);
	}
	.confirm.danger {
		background: var(--color-danger);
	}
	.confirm.danger:hover {
		background: #c62828;
	}
</style>
