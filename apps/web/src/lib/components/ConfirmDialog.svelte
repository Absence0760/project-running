<script lang="ts">
	import Modal from './Modal.svelte';

	interface Props {
		open: boolean;
		title: string;
		message: string;
		confirmLabel?: string;
		cancelLabel?: string;
		danger?: boolean;
		onconfirm: () => void | Promise<void>;
		oncancel: () => void;
		/// When set, the confirm button stays disabled until the user types
		/// this exact string (case-insensitive, trimmed) into a challenge
		/// input. Used for irreversible actions (e.g. account deletion —
		/// Apple 5.1.1 / data-loss confirmation) so a stray click can't
		/// trigger them.
		requireText?: string;
		requireTextLabel?: string;
		/// Forwarded to the rendered backdrop element so e2e specs
		/// can target a specific confirm dialog (e.g. distinguishing
		/// share-confirm-dialog from delete-confirm-dialog on the
		/// same page). Mirrors the `data-testid` pattern already
		/// used on the Modal primitive.
		'data-testid'?: string;
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
		requireText,
		requireTextLabel,
		'data-testid': testId,
	}: Props = $props();

	let challenge = $state('');
	// While the async `onconfirm` is in flight, both buttons disable so a
	// fast double-click can't fire the (often destructive, non-idempotent)
	// action twice, and the dialog can't be dismissed out from under it.
	let busy = $state(false);
	// Reset the challenge whenever the dialog reopens so a prior entry
	// can't carry over.
	$effect(() => {
		if (!open) {
			challenge = '';
			busy = false;
		}
	});
	const challengeMet = $derived(
		!requireText || challenge.trim().toLowerCase() === requireText.trim().toLowerCase(),
	);

	async function handleConfirm() {
		if (!challengeMet || busy) return;
		busy = true;
		try {
			await onconfirm();
		} finally {
			busy = false;
		}
	}
</script>

<Modal
	{open}
	{title}
	narrow
	onclose={() => {
		if (!busy) oncancel();
	}}
	bodyClass="confirm-body"
	data-testid={testId}
>
	<p>{message}</p>
	{#if requireText}
		<label class="challenge">
			<span class="challenge-label">
				{requireTextLabel ?? `Type "${requireText}" to confirm`}
			</span>
			<input
				type="text"
				class="challenge-input"
				bind:value={challenge}
				autocomplete="off"
				autocapitalize="off"
				spellcheck="false"
				data-testid="confirm-challenge-input"
			/>
		</label>
	{/if}
	<div class="actions">
		<button type="button" class="btn btn-secondary" onclick={oncancel} disabled={busy}>
			{cancelLabel}
		</button>
		<button
			type="button"
			class="btn"
			class:btn-primary={!danger}
			class:btn-danger={danger}
			disabled={!challengeMet || busy}
			aria-busy={busy}
			onclick={handleConfirm}
		>
			{#if busy}<span class="confirm-spinner" aria-hidden="true"></span>{/if}
			{confirmLabel}
		</button>
	</div>
</Modal>

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
	.challenge {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.challenge-label {
		font-size: 0.82rem;
		color: var(--color-text-secondary);
	}
	.challenge-input {
		padding: var(--space-xs) var(--space-sm);
		font-size: 0.9rem;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-bg);
		color: var(--color-text);
	}
	.confirm-spinner {
		display: inline-block;
		width: 0.85em;
		height: 0.85em;
		margin-inline-end: 0.4rem;
		vertical-align: -0.1em;
		border: 2px solid currentColor;
		border-inline-end-color: transparent;
		border-radius: 50%;
		animation: confirm-spin 0.6s linear infinite;
	}
	@keyframes confirm-spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.confirm-spinner {
			animation: none;
		}
	}
</style>
