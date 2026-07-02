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
	// In-flight guard for an incoming-request response so a double-click
	// can't fire confirm/decline twice.
	let respondingId = $state<string | null>(null);
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
		await auth.ready();
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
			showToast(m('safety.removeFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			confirmingRemove = null;
		}
	}

	async function handleConfirm(req: PendingSafetyRequest) {
		if (respondingId) return;
		respondingId = req.id;
		try {
			await confirmSafetyRequest(req.id);
			await reload();
			showToast(m('safety.confirmedToast'), 'success');
		} catch (e) {
			showToast(m('safety.addFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			respondingId = null;
		}
	}

	async function handleDecline(req: PendingSafetyRequest) {
		if (respondingId) return;
		respondingId = req.id;
		try {
			await declineSafetyRequest(req.id);
			await reload();
			showToast(m('safety.declinedToast'), 'info');
		} catch (e) {
			showToast(m('safety.addFailed', { error: e instanceof Error ? e.message : String(e) }), 'error');
		} finally {
			respondingId = null;
		}
	}
</script>

<svelte:head>
	<title>{m('safety.title')}</title>
</svelte:head>

<div class="page">
	<header class="page-head">
		<p class="kicker">{m('safety.kicker')}</p>
		<h1>{m('safety.title')}</h1>
		<p class="tagline">{m('safety.intro')}</p>
	</header>

	<section class="card">
		<form
			class="add-row"
			onsubmit={(e) => {
				e.preventDefault();
				handleAdd();
			}}
		>
			<label class="field">
				<span class="label-text">{m('safety.addLabel')}</span>
				<input
					type="email"
					bind:value={email}
					placeholder="partner@example.com"
					autocomplete="email"
					data-testid="safety-email-input"
				/>
			</label>
			<button type="submit" class="btn-primary" disabled={adding} data-testid="safety-add-button">
				{#if adding}
					<span class="material-symbols spin" aria-hidden="true">progress_activity</span>
					{m('safety.adding')}
				{:else}
					<span class="material-symbols" aria-hidden="true">person_add</span>
					{m('safety.addButton')}
				{/if}
			</button>
		</form>

		{#if loading}
			<div class="skel-list" aria-hidden="true">
				<span class="skel skel-row"></span>
				<span class="skel skel-row"></span>
			</div>
			<p class="sr-only" role="status">{m('safety.loading')}</p>
		{:else}
			<ul class="contact-list" data-testid="safety-contact-list">
				{#each contacts as c (c.id)}
					<li class="contact" data-testid="safety-contact">
						<div class="who">
							<span class="email">{c.contact_email}</span>
							<span class="badge" class:confirmed={c.confirmed_at} class:pending={!c.confirmed_at}>
								<span class="material-symbols" aria-hidden="true">
									{c.confirmed_at ? 'check_circle' : 'schedule'}
								</span>
								{c.confirmed_at ? m('safety.statusConfirmed') : m('safety.statusPending')}
							</span>
						</div>
						<button
							class="btn-danger btn-sm"
							onclick={() => (confirmingRemove = c)}
							aria-label={m('safety.remove')}
						>
							<span class="material-symbols" aria-hidden="true">delete</span>
							{m('safety.remove')}
						</button>
					</li>
				{:else}
					<li class="empty-state" data-testid="safety-empty">
						<span class="material-symbols" aria-hidden="true">shield_person</span>
						<p class="empty-title">{m('safety.empty')}</p>
						<p class="empty-hint">{m('safety.emptyHint')}</p>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	{#if pending.length > 0}
		<section class="card incoming" data-testid="safety-incoming">
			<header class="section-head">
				<h2>{m('safety.incomingTitle')}</h2>
				<p class="tagline">{m('safety.incomingIntro')}</p>
			</header>
			<ul class="contact-list">
				{#each pending as req (req.id)}
					<li class="contact">
						<span class="who">
							<span class="material-symbols req-icon" aria-hidden="true">person</span>
							{m('safety.incomingFrom', { name: req.owner_name || m('safety.unknownRunner') })}
						</span>
						<span class="actions">
							<button class="btn-primary btn-sm" onclick={() => handleConfirm(req)} disabled={respondingId !== null} data-testid="safety-confirm-request">
								{m('safety.confirm')}
							</button>
							<button class="btn-outline btn-sm" onclick={() => handleDecline(req)} disabled={respondingId !== null}>
								{m('safety.decline')}
							</button>
						</span>
					</li>
				{/each}
			</ul>
		</section>
	{/if}
</div>

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
	.page { padding: var(--space-xl) var(--space-2xl); max-width: 48rem; }
	.page-head { margin-bottom: var(--space-xl); }
	.kicker {
		font-size: 0.72rem;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		color: var(--color-text-tertiary);
		margin: 0 0 var(--space-2xs);
	}
	h1 { margin: 0 0 var(--space-sm); font-size: 1.6rem; }
	.tagline {
		color: var(--color-text-secondary);
		margin: 0;
		line-height: 1.5;
		max-width: 40rem;
	}
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-lg);
		margin-bottom: var(--space-xl);
	}

	.add-row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-md);
		padding-bottom: var(--space-lg);
		margin-bottom: var(--space-lg);
		border-bottom: 1px solid var(--color-border);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		flex: 1;
		min-width: 0;
	}
	.label-text {
		font-size: 0.82rem;
		font-weight: 500;
		color: var(--color-text-secondary);
	}
	.add-row input {
		width: 100%;
		padding: var(--space-sm) var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		font-size: 0.9rem;
		background: var(--color-bg);
	}

	.contact-list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.contact {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-md);
		padding: var(--space-md);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-bg-tertiary);
	}
	.who {
		display: flex;
		flex-direction: column;
		gap: var(--space-2xs);
		min-width: 0;
	}
	.email {
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.badge {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		align-self: flex-start;
		font-size: 0.75rem;
		font-weight: 600;
		padding: 0.15rem 0.5rem;
		border-radius: var(--radius-full, 999px);
		line-height: 1.4;
	}
	.badge .material-symbols { font-size: 0.95rem; }
	.badge.confirmed {
		color: var(--color-primary);
		background: var(--color-primary-light);
	}
	.badge.pending {
		color: var(--color-warning, #92600a);
		background: color-mix(in srgb, var(--color-warning, #d99a2b) 15%, transparent);
	}
	.actions {
		display: flex;
		gap: var(--space-sm);
		flex-shrink: 0;
	}

	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: var(--space-2xs);
		padding: var(--space-xl) var(--space-md);
		color: var(--color-text-secondary);
	}
	.empty-state .material-symbols {
		font-size: 2.25rem;
		color: var(--color-text-tertiary);
		margin-bottom: var(--space-2xs);
	}
	.empty-title { margin: 0; font-weight: 600; color: var(--color-text); }
	.empty-hint { margin: 0; font-size: 0.86rem; line-height: 1.5; max-width: 30rem; }

	.section-head { margin-bottom: var(--space-md); }
	.section-head h2 { margin: 0 0 var(--space-2xs); font-size: 1.05rem; }
	.incoming .who {
		flex-direction: row;
		align-items: center;
		gap: var(--space-sm);
	}
	.req-icon {
		font-size: 1.3rem;
		color: var(--color-text-tertiary);
		flex-shrink: 0;
	}

	.skel-list { display: flex; flex-direction: column; gap: var(--space-sm); }
	.skel {
		display: block;
		background: linear-gradient(
			90deg,
			var(--color-bg-tertiary) 25%,
			var(--color-border) 50%,
			var(--color-bg-tertiary) 75%
		);
		background-size: 200% 100%;
		animation: shimmer 1.4s ease-in-out infinite;
		border-radius: var(--radius-md);
	}
	.skel-row { height: 3.25rem; }
	@keyframes shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}

	.material-symbols {
		font-family: 'Material Symbols Outlined', system-ui;
		font-weight: normal;
		font-style: normal;
		display: inline-block;
		line-height: 1;
	}
	.spin { animation: spin 0.9s linear infinite; }
	@keyframes spin { to { transform: rotate(360deg); } }

	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
	}

	@media (prefers-reduced-motion: reduce) {
		.skel { animation: none; }
		.spin { animation: none; }
	}
</style>
