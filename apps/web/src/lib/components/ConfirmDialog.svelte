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
	<div class="modal-backdrop" onclick={oncancel} role="presentation"></div>
	<div class="modal modal-narrow" role="alertdialog" aria-modal="true" aria-label={title}>
		<header class="modal-header">
			<h2>{title}</h2>
			<button class="modal-close" type="button" aria-label="Close" onclick={oncancel}>
				<span class="material-symbols">close</span>
			</button>
		</header>
		<div class="modal-body confirm-body">
			<p>{message}</p>
			<div class="actions">
				<button type="button" class="btn btn-secondary" onclick={oncancel}>
					{cancelLabel}
				</button>
				<button
					type="button"
					class="btn"
					class:btn-primary={!danger}
					class:btn-danger={danger}
					onclick={onconfirm}
				>
					{confirmLabel}
				</button>
			</div>
		</div>
	</div>
{/if}

<style>
	/* Canonical .modal-* classes live in app.css. */
	.confirm-body {
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	.confirm-body p {
		font-size: 0.88rem;
		color: var(--color-text-secondary);
		line-height: 1.5;
		margin: 0;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
</style>
