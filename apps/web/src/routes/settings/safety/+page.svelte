<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import {
		fetchMySafetyContacts,
		addSafetyContact,
		removeSafetyContact,
		fetchPendingSafetyRequests,
		confirmSafetyRequest,
		declineSafetyRequest,
		type SafetyContact,
		type PendingSafetyRequest,
	} from '$lib/core/data';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';

	let contacts = $state<SafetyContact[]>([]);
	let pending = $state<PendingSafetyRequest[]>([]);
	let loading = $state(true);
	let email = $state('');
	let adding = $state(false);
	let confirmingRemove = $state<SafetyContact | null>(null);

	// Mirror the server-side CHECK so the user gets an inline message before
	// a round trip that would 23514.
	const emailRe = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

	async function reload() {
		[contacts, pending] = await Promise.all([
			fetchMySafetyContacts(),
			fetchPendingSafetyRequests(),
		]);
	}

	onMount(async () => {
		for (let i = 0; i < 20 && (auth.loading || !auth.user); i++) {
			await new Promise((r) => setTimeout(r, 50));
		}
		if (!auth.user) return;
		await reload();
		loading = false;
	});

	async function handleAdd() {
		const value = email.trim();
		if (!emailRe.test(value)) {
			showToast(m('safety.invalidEmail'), 'error');
			return;
		}
		adding = true;
		try {
			await addSafetyContact(value);
			email = '';
			await reload();
			showToast(m('safety.addedToast'), 'success');
		} catch (e) {
			showToast(m('safety.addFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			adding = false;
		}
	}

	async function handleRemove(c: SafetyContact) {
		try {
			await removeSafetyContact(c.id);
			await reload();
			showToast(m('safety.removedToast'), 'info');
		} catch (e) {
			showToast(m('safety.addFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			confirmingRemove = null;
		}
	}

	async function handleConfirm(req: PendingSafetyRequest) {
		try {
			await confirmSafetyRequest(req.id);
			await reload();
			showToast(m('safety.confirmedToast'), 'success');
		} catch (e) {
			showToast(m('safety.addFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}

	async function handleDecline(req: PendingSafetyRequest) {
		try {
			await declineSafetyRequest(req.id);
			await reload();
			showToast(m('safety.declinedToast'), 'info');
		} catch (e) {
			showToast(m('safety.addFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		}
	}
</script>

<svelte:head>
	<title>{m('safety.title')}</title>
</svelte:head>

<section class="safety">
	<h1>{m('safety.title')}</h1>
	<p class="intro">{m('safety.intro')}</p>

	<form
		class="add-row"
		onsubmit={(e) => {
			e.preventDefault();
			handleAdd();
		}}
	>
		<label class="field">
			<span>{m('safety.addLabel')}</span>
			<input
				type="email"
				bind:value={email}
				placeholder="partner@example.com"
				autocomplete="email"
				data-testid="safety-email-input"
			/>
		</label>
		<button type="submit" class="btn-primary" disabled={adding} data-testid="safety-add-button">
			{adding ? m('safety.adding') : m('safety.addButton')}
		</button>
	</form>

	{#if loading}
		<p class="muted">…</p>
	{:else}
		<ul class="contact-list" data-testid="safety-contact-list">
			{#each contacts as c (c.id)}
				<li class="contact" data-testid="safety-contact">
					<div class="who">
						<span class="email">{c.contact_email}</span>
						<span class="status" class:confirmed={c.confirmed_at}>
							{c.confirmed_at ? m('safety.statusConfirmed') : m('safety.statusPending')}
						</span>
					</div>
					<button class="btn-text danger" onclick={() => (confirmingRemove = c)}>
						{m('safety.remove')}
					</button>
				</li>
			{:else}
				<li class="muted empty">{m('safety.empty')}</li>
			{/each}
		</ul>
	{/if}

	{#if pending.length > 0}
		<div class="incoming" data-testid="safety-incoming">
			<h2>{m('safety.incomingTitle')}</h2>
			<p class="intro">{m('safety.incomingIntro')}</p>
			<ul class="contact-list">
				{#each pending as req (req.id)}
					<li class="contact">
						<span class="who">{m('safety.incomingFrom', { name: req.owner_name || m('safety.unknownRunner') })}</span>
						<span class="actions">
							<button class="btn-primary sm" onclick={() => handleConfirm(req)} data-testid="safety-confirm-request">
								{m('safety.confirm')}
							</button>
							<button class="btn-text" onclick={() => handleDecline(req)}>
								{m('safety.decline')}
							</button>
						</span>
					</li>
				{/each}
			</ul>
		</div>
	{/if}
</section>

<ConfirmDialog
	open={confirmingRemove !== null}
	title={m('safety.title')}
	message={m('safety.removeConfirm')}
	confirmLabel={m('safety.remove')}
	danger
	onconfirm={() => {
		if (confirmingRemove) handleRemove(confirmingRemove);
	}}
	oncancel={() => (confirmingRemove = null)}
/>

<style>
	.safety {
		max-width: 640px;
	}
	h1 {
		margin: 0 0 0.5rem;
	}
	h2 {
		margin: 0 0 0.5rem;
		font-size: 1.1rem;
	}
	.intro {
		color: var(--color-text-muted, #6b7280);
		margin: 0 0 1.25rem;
		line-height: 1.5;
	}
	.add-row {
		display: flex;
		align-items: flex-end;
		gap: 0.75rem;
		margin-bottom: 1.5rem;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		flex: 1;
	}
	.field span {
		font-size: 0.85rem;
		color: var(--color-text-muted, #6b7280);
	}
	input {
		padding: 0.55rem 0.7rem;
		border: 1px solid var(--color-border, #d1d5db);
		border-radius: 8px;
		font-size: 0.95rem;
	}
	.contact-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.contact {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
		padding: 0.7rem 0.85rem;
		border: 1px solid var(--color-border, #e5e7eb);
		border-radius: 10px;
	}
	.who {
		display: flex;
		flex-direction: column;
		gap: 0.15rem;
		min-width: 0;
	}
	.email {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.status {
		font-size: 0.8rem;
		color: var(--color-text-muted, #9ca3af);
	}
	.status.confirmed {
		color: var(--color-primary, #2c5f6e);
	}
	.actions {
		display: flex;
		gap: 0.5rem;
		flex-shrink: 0;
	}
	.incoming {
		margin-top: 2rem;
		padding-top: 1.25rem;
		border-top: 1px solid var(--color-border, #e5e7eb);
	}
	.empty {
		padding: 0.7rem 0;
	}
	.btn-primary {
		background: var(--color-primary, #2c5f6e);
		color: #fff;
		border: none;
		border-radius: 8px;
		padding: 0.55rem 1rem;
		font-weight: 600;
		cursor: pointer;
	}
	.btn-primary.sm {
		padding: 0.4rem 0.8rem;
		font-size: 0.85rem;
	}
	.btn-primary:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.btn-text {
		background: none;
		border: none;
		color: var(--color-text-muted, #6b7280);
		cursor: pointer;
		font-size: 0.9rem;
	}
	.btn-text.danger {
		color: var(--color-danger, #b91c1c);
	}
	.muted {
		color: var(--color-text-muted, #9ca3af);
	}
</style>
