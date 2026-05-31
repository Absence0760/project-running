<script lang="ts">
	import Modal from './Modal.svelte';
	import {
		submitReport,
		type ReportReason,
		type ReportTargetKind,
	} from '$lib/core/data';
	import { showToast } from '$lib/stores/toast.svelte';

	interface Props {
		open: boolean;
		targetKind: ReportTargetKind;
		targetId: string;
		/// Human-readable name of the thing being reported. Surfaced
		/// in the dialog body so the user can sanity-check what they're
		/// flagging — Reports submitted by misclick are the most
		/// common false positive in any moderation queue.
		targetLabel?: string;
		onclose: () => void;
	}

	let { open, targetKind, targetId, targetLabel, onclose }: Props = $props();

	const REASONS: { value: ReportReason; label: string; hint: string }[] = [
		{
			value: 'spam',
			label: 'Spam or promotion',
			hint: 'Commercial pitches, link farms, repeated identical content.',
		},
		{
			value: 'harassment',
			label: 'Harassment or abuse',
			hint: 'Targeted attacks, threats, hateful language.',
		},
		{
			value: 'inappropriate',
			label: 'Inappropriate content',
			hint: 'Adult, violent, or otherwise off-topic for a running app.',
		},
		{
			value: 'impersonation',
			label: 'Impersonation',
			hint: 'Pretending to be a specific real person, brand, or club.',
		},
		{ value: 'other', label: 'Other', hint: 'Tell us what’s wrong below.' },
	];

	let reason = $state<ReportReason>('spam');
	let notes = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);

	const targetNoun = $derived(
		targetKind === 'user' ? 'profile' : targetKind === 'club' ? 'club' : 'route',
	);

	function reset() {
		reason = 'spam';
		notes = '';
		error = null;
		busy = false;
	}

	function handleClose() {
		reset();
		onclose();
	}

	async function handleSubmit() {
		if (busy) return;
		busy = true;
		error = null;
		try {
			await submitReport({
				targetKind,
				targetId,
				reason,
				notes: notes.trim() || undefined,
			});
			showToast('Report submitted. Thanks for flagging.', 'success');
			handleClose();
		} catch (e) {
			error = e instanceof Error ? e.message : 'Failed to submit report.';
		} finally {
			busy = false;
		}
	}
</script>

<Modal {open} title="Report this {targetNoun}" narrow onclose={handleClose} bodyClass="report-body">
	{#if targetLabel}
		<p class="target">
			You're reporting <strong>{targetLabel}</strong>. Reports are reviewed manually;
			only you can see the reports you file.
		</p>
	{:else}
		<p class="target">
			Reports are reviewed manually; only you can see the reports you file.
		</p>
	{/if}

	<fieldset>
		<legend class="section-label">Reason</legend>
		{#each REASONS as r (r.value)}
			<label class="radio">
				<input type="radio" name="reason" value={r.value} bind:group={reason} />
				<span>
					<strong>{r.label}</strong>
					<span class="hint">{r.hint}</span>
				</span>
			</label>
		{/each}
	</fieldset>

	<label class="notes-field">
		<span class="section-label">Notes <span class="optional">optional</span></span>
		<textarea
			bind:value={notes}
			rows="3"
			maxlength="600"
			placeholder="Anything that would help a moderator understand the issue."
		></textarea>
	</label>

	{#if error}
		<p class="error" role="alert">{error}</p>
	{/if}

	<div class="actions">
		<button type="button" class="btn btn-secondary" onclick={handleClose} disabled={busy}>
			Cancel
		</button>
		<button type="button" class="btn btn-primary" onclick={handleSubmit} disabled={busy}>
			{busy ? 'Submitting…' : 'Submit report'}
		</button>
	</div>
</Modal>

<style>
	/* Canonical .modal-* classes live in app.css. */
	.report-body {
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	.target {
		font-size: 0.85rem;
		color: var(--color-text-secondary);
		line-height: 1.45;
		margin: 0;
	}
	fieldset {
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.7rem 0.9rem;
		background: var(--color-surface);
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	legend.section-label {
		font-weight: 600;
		font-size: 0.85rem;
		padding: 0 0.3rem;
	}
	.radio {
		display: flex;
		flex-direction: row;
		align-items: flex-start;
		gap: 0.5rem;
		font-weight: 500;
		font-size: 0.88rem;
		cursor: pointer;
	}
	.radio input {
		margin-top: 0.3rem;
	}
	.radio span {
		display: flex;
		flex-direction: column;
	}
	.radio .hint {
		font-weight: 400;
		color: var(--color-text-secondary);
		font-size: 0.8rem;
		line-height: 1.4;
	}
	.notes-field {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.notes-field .section-label {
		font-weight: 600;
		font-size: 0.85rem;
	}
	.optional {
		font-weight: 400;
		color: var(--color-text-tertiary);
		font-size: 0.78rem;
	}
	textarea {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 0.5rem 0.7rem;
		font: inherit;
		color: inherit;
		resize: vertical;
	}
	textarea:focus {
		outline: none;
		border-color: var(--color-primary);
		box-shadow: 0 0 0 3px var(--color-primary-light);
	}
	/* audit/accessibility (May 2026) WCAG 2.4.7 + 2.4.11: pair the
	   :focus rule above with :focus-visible so keyboard users get a real
	   outline. The :focus rule still removes the default ring on mouse
	   focus (no visible outline on click); :focus-visible re-adds a
	   proper one for keyboard / programmatic focus. */
	textarea:focus-visible {
		outline: 2px solid var(--color-primary);
		outline-offset: 2px;
	}

	.error {
		color: var(--color-danger);
		background: var(--color-danger-light);
		padding: 0.5rem 0.7rem;
		border-radius: var(--radius-md);
		font-size: 0.85rem;
		margin: 0;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
	}
</style>
