<script lang="ts">
	import { m } from '$lib/i18n/store.svelte';
	import { toast } from '$lib/stores/toast.svelte';
	import {
		createFundraiser,
		updateFundraiser,
		fetchPayoutAccount,
		type CreateFundraiserInput
	} from '$lib/core/data';
	import type { Fundraiser } from '$lib/types';
	import { onMount } from 'svelte';

	let {
		runId = null,
		eventId = null,
		existing = null,
		oncreated,
		oncancel
	}: {
		runId?: string | null;
		eventId?: string | null;
		existing?: Fundraiser | null;
		oncreated?: (f: Fundraiser) => void;
		oncancel?: () => void;
	} = $props();

	let charityName = $state(existing?.charity_name ?? '');
	let charityUrl = $state(existing?.charity_url ?? '');
	let title = $state(existing?.title ?? '');
	let story = $state(existing?.story ?? '');
	// Goal entered in major units; stored in cents.
	let goalMajor = $state<number | null>(existing ? existing.goal_cents / 100 : null);

	let chargesEnabled = $state(false);
	let loadingGate = $state(true);
	let saving = $state(false);

	onMount(async () => {
		const acct = await fetchPayoutAccount();
		chargesEnabled = acct?.charges_enabled ?? false;
		loadingGate = false;
	});

	const canSave = $derived(
		chargesEnabled &&
			charityName.trim().length > 0 &&
			title.trim().length > 0 &&
			goalMajor != null &&
			goalMajor > 0
	);

	async function save() {
		if (!canSave || saving) return;
		saving = true;
		try {
			const goalCents = Math.round((goalMajor as number) * 100);
			if (existing) {
				await updateFundraiser(existing.id, {
					charityName,
					charityUrl,
					title,
					story,
					goalCents
				});
				oncreated?.({ ...existing, charity_name: charityName, title, goal_cents: goalCents });
			} else {
				const input: CreateFundraiserInput = {
					charityName,
					charityUrl,
					title,
					story,
					goalCents,
					runId,
					eventId
				};
				const created = await createFundraiser(input);
				oncreated?.(created);
			}
		} catch (e) {
			toast.error(m('fundraiser.saveFailed'));
			console.error('fundraiser save failed', e);
		} finally {
			saving = false;
		}
	}
</script>

<form class="editor-form" onsubmit={(e) => { e.preventDefault(); save(); }}>
	{#if !loadingGate && !chargesEnabled}
		<p class="payouts-gate" data-testid="fundraiser-needs-payout">
			{m('fundraiser.payoutsRequired')}
			<a href="/settings/payouts">{m('fundraiser.setUpPayouts')}</a>
		</p>
	{/if}

	<label>
		<span>{m('fundraiser.title')}</span>
		<input type="text" bind:value={title} required maxlength="120" data-testid="fundraiser-title" />
	</label>

	<label>
		<span>{m('fundraiser.charityName')}</span>
		<input type="text" bind:value={charityName} required maxlength="120" data-testid="fundraiser-charity" />
	</label>

	<label>
		<span>{m('fundraiser.charityUrl')}</span>
		<input type="url" bind:value={charityUrl} placeholder="https://" inputmode="url" />
	</label>

	<label>
		<span>{m('fundraiser.goal')}</span>
		<input type="number" bind:value={goalMajor} min="1" step="1" required data-testid="fundraiser-goal" />
	</label>

	<label>
		<span>{m('fundraiser.story')}</span>
		<textarea bind:value={story} rows="4" maxlength="2000"></textarea>
	</label>

	<div class="actions">
		<button type="button" class="btn btn-secondary" onclick={() => oncancel?.()}>
			{m('fundraiser.cancel')}
		</button>
		<button type="submit" class="btn btn-primary" disabled={!canSave || saving} data-testid="fundraiser-save">
			{m('fundraiser.save')}
		</button>
	</div>
</form>

<style>
	.payouts-gate {
		padding: var(--space-sm);
		border-radius: var(--radius-md, 8px);
		background: var(--color-surface-alt, #f3f4f6);
		color: var(--color-text-muted, #6b7280);
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--space-sm);
	}
</style>
