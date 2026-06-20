<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import Modal from '$lib/components/Modal.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import GoalThermometer from '$lib/components/GoalThermometer.svelte';
	import DonationFeed from '$lib/components/DonationFeed.svelte';
	import FundraiserEditor from '$lib/components/FundraiserEditor.svelte';
	import {
		fetchFundraiserById,
		fetchFundraiserTotals,
		fetchFundraiserFeed,
		startDonationCheckout,
		closeFundraiser
	} from '$lib/core/data';
	import type { Fundraiser, FundraiserFeedEntry, FundraiserTotals } from '$lib/types';

	let { data }: { data: { id: string; donated: string | null } } = $props();

	let loading = $state(true);
	let fundraiser = $state<Fundraiser | null>(null);
	let totals = $state<FundraiserTotals | null>(null);
	let feed = $state<FundraiserFeedEntry[]>([]);

	let donateOpen = $state(false);
	let editOpen = $state(false);
	let confirmCloseOpen = $state(false);
	let donating = $state(false);

	// Donation form (amount in major units; cents on submit).
	let amountMajor = $state<number | null>(null);
	let donorName = $state('');
	let donorMessage = $state('');
	let anonymous = $state(false);

	const isOwner = $derived(!!fundraiser && auth.user?.id === fundraiser.owner_user_id);
	const closed = $derived(fundraiser?.status === 'closed');
	const justDonated = $derived(data.donated === '1');

	async function refreshTotalsFeed() {
		const [t, f] = await Promise.all([
			fetchFundraiserTotals(data.id),
			fetchFundraiserFeed(data.id, 50)
		]);
		totals = t;
		feed = f;
	}

	async function load() {
		loading = true;
		fundraiser = await fetchFundraiserById(data.id);
		if (fundraiser) await refreshTotalsFeed();
		loading = false;
	}

	onMount(async () => {
		await load();
		// Post-checkout success poll: the webhook is the sole writer, so the
		// donation lands a beat after redirect. Re-poll the public totals/feed a
		// few times so the thermometer + feed reflect the new donation without a
		// manual refresh. Never trust the redirect itself as payment success.
		if (justDonated && fundraiser) {
			for (let i = 0; i < 5; i++) {
				await new Promise((r) => setTimeout(r, 1500));
				await refreshTotalsFeed();
			}
		}
	});

	async function submitDonation() {
		if (donating || !fundraiser) return;
		const cents = amountMajor != null ? Math.round(amountMajor * 100) : 0;
		if (cents <= 0) return;
		donating = true;
		try {
			const { url } = await startDonationCheckout(fundraiser.id, cents, {
				displayName: anonymous ? null : donorName.trim() || null,
				message: donorMessage.trim() || null,
				isAnonymous: anonymous
			});
			window.location.href = url;
		} catch (e) {
			showToast(m('fundraiser.donateFailed'), 'error');
			console.error('donation checkout failed', e);
			donating = false;
		}
	}

	function onEdited(updated: Fundraiser) {
		fundraiser = updated;
		editOpen = false;
	}

	async function doClose() {
		if (!fundraiser) return;
		try {
			await closeFundraiser(fundraiser.id);
			fundraiser = { ...fundraiser, status: 'closed' };
		} catch (e) {
			showToast(m('fundraiser.closeFailed'), 'error');
			console.error('fundraiser close failed', e);
		} finally {
			confirmCloseOpen = false;
		}
	}

	async function share() {
		const url = `${location.origin}/fundraisers/${data.id}`;
		try {
			if (navigator.share) {
				await navigator.share({ title: fundraiser?.title ?? '', url });
			} else {
				await navigator.clipboard.writeText(url);
				showToast(m('fundraiser.shareCopied'), 'success');
			}
		} catch {
			/* user dismissed the share sheet — non-fatal */
		}
	}
</script>

<svelte:head>
	<title>{fundraiser?.title ?? m('fundraiser.loading')}</title>
</svelte:head>

<main class="fundraiser-page">
	{#if loading}
		<p class="state">{m('fundraiser.loading')}</p>
	{:else if !fundraiser}
		<p class="state">{m('fundraiser.notFound')}</p>
	{:else}
		{#if justDonated}
			<div class="thanks card" role="status" data-testid="donation-thanks">
				<strong>{m('fundraiser.thanksTitle')}</strong>
				<p>{m('fundraiser.thanksBody')}</p>
			</div>
		{/if}

		<header class="hero">
			<div class="hero-head">
				<h1>{fundraiser.title}</h1>
				<div class="hero-actions">
					<button type="button" class="btn btn-secondary" onclick={share}>
						{m('fundraiser.share')}
					</button>
					{#if isOwner}
						<button type="button" class="btn btn-secondary" onclick={() => (editOpen = true)}>
							{m('fundraiser.editCta')}
						</button>
						{#if !closed}
							<button
								type="button"
								class="btn btn-secondary"
								onclick={() => (confirmCloseOpen = true)}
							>
								{m('fundraiser.close')}
							</button>
						{/if}
					{/if}
				</div>
			</div>
			<p class="charity">
				{#if fundraiser.charity_url}
					<a href={fundraiser.charity_url} target="_blank" rel="noopener noreferrer nofollow"
						>{fundraiser.charity_name}</a
					>
				{:else}
					{fundraiser.charity_name}
				{/if}
			</p>
		</header>

		<section class="card thermometer-card">
			<GoalThermometer
				raisedCents={totals?.raised_cents ?? 0}
				goalCents={totals?.goal_cents ?? fundraiser.goal_cents}
				donorCount={totals?.donor_count ?? 0}
				currency={fundraiser.currency}
			/>
			{#if closed}
				<p class="closed">{m('fundraiser.closed')}</p>
			{:else}
				<button
					type="button"
					class="btn btn-primary btn-donate"
					onclick={() => (donateOpen = true)}
					data-testid="donate-cta"
				>
					{m('fundraiser.donate')}
				</button>
			{/if}
		</section>

		{#if fundraiser.story}
			<section class="card story">
				<p>{fundraiser.story}</p>
			</section>
		{/if}

		<section class="card feed-card">
			<h2>{m('fundraiser.feedTitle')}</h2>
			<DonationFeed entries={feed} />
		</section>

		<Modal open={donateOpen} onclose={() => (donateOpen = false)} title={m('fundraiser.donate')} narrow>
			<form
				class="editor-form donate-form"
				onsubmit={(e) => {
					e.preventDefault();
					submitDonation();
				}}
			>
				<label>
					<span>{m('fundraiser.donateAmount')}</span>
					<input
						type="number"
						bind:value={amountMajor}
						min="1"
						step="1"
						required
						data-testid="donate-amount"
					/>
				</label>
				<label class="toggle-row">
					<input type="checkbox" bind:checked={anonymous} data-testid="donate-anon" />
					<span>{m('fundraiser.donateAnonymously')}</span>
				</label>
				{#if !anonymous}
					<label>
						<span>{m('fundraiser.donateName')}</span>
						<input type="text" bind:value={donorName} maxlength="80" />
					</label>
				{/if}
				<label>
					<span>{m('fundraiser.donateMessage')}</span>
					<textarea bind:value={donorMessage} rows="3" maxlength="280"></textarea>
				</label>
				<div class="actions">
					<button type="button" class="btn btn-secondary" onclick={() => (donateOpen = false)}>
						{m('fundraiser.cancel')}
					</button>
					<button
						type="submit"
						class="btn btn-primary"
						disabled={donating || amountMajor == null || amountMajor <= 0}
						data-testid="donate-submit"
					>
						{m('fundraiser.donateSubmit')}
					</button>
				</div>
			</form>
		</Modal>

		<Modal open={editOpen} onclose={() => (editOpen = false)} title={m('fundraiser.editCta')}>
			<FundraiserEditor
				existing={fundraiser}
				oncreated={onEdited}
				oncancel={() => (editOpen = false)}
			/>
		</Modal>

		<ConfirmDialog
			open={confirmCloseOpen}
			title={m('fundraiser.close')}
			message={m('fundraiser.closeConfirm')}
			confirmLabel={m('fundraiser.close')}
			cancelLabel={m('fundraiser.cancel')}
			danger
			onconfirm={doClose}
			oncancel={() => (confirmCloseOpen = false)}
		/>
	{/if}
</main>

<style>
	.fundraiser-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
		display: flex;
		flex-direction: column;
		gap: var(--space-lg);
	}
	.state {
		color: var(--color-text-muted, #6b7280);
	}
	.hero-head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: var(--space-md);
		flex-wrap: wrap;
	}
	.hero h1 {
		margin: 0;
	}
	.hero-actions {
		display: flex;
		gap: var(--space-sm);
		flex-wrap: wrap;
	}
	.charity {
		margin: var(--space-xs) 0 0;
		color: var(--color-text-muted, #6b7280);
	}
	.thermometer-card,
	.story,
	.feed-card {
		padding: var(--space-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
	.feed-card h2 {
		margin: 0;
		font-size: 1.1rem;
	}
	.btn-donate {
		align-self: flex-start;
	}
	.thanks {
		padding: var(--space-md) var(--space-lg);
		background: var(--color-success-bg, #ecfdf5);
		border: 1px solid var(--color-success, #16a34a);
	}
	.thanks p {
		margin: var(--space-2xs) 0 0;
	}
	.closed {
		color: var(--color-text-muted, #6b7280);
		font-weight: 600;
		margin: 0;
	}
	.story p {
		margin: 0;
		white-space: pre-wrap;
	}
	.donate-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-md);
	}
</style>
