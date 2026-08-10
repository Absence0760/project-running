<script lang="ts">
	import { onMount } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';
	import Modal from './Modal.svelte';
	import FundraiserCard from './FundraiserCard.svelte';
	import FundraiserEditor from './FundraiserEditor.svelte';
	import {
		fetchFundraiserForRun,
		fetchFundraiserForEvent,
		fetchFundraiserTotals
	} from '$lib/core/data';
	import { fundraisingEnabled } from '$lib/social/fundraising_flag';
	import type { Fundraiser, FundraiserTotals } from '$lib/types';

	// Fail-closed: hide every donation affordance until Stripe Connect +
	// the compliance sign-off land (PUBLIC_FUNDRAISING_ENABLED). Off → the
	// section (view + owner "Create fundraiser" CTA) renders nothing and
	// never fetches, so nobody hits a donate flow that would 503.
	const fundraisingOn = fundraisingEnabled();

	// Anchor is exactly one of runId / eventId (mirrors the fundraisers CHECK).
	let {
		runId = null,
		eventId = null,
		isOwner = false
	}: {
		runId?: string | null;
		eventId?: string | null;
		isOwner?: boolean;
	} = $props();

	let loading = $state(true);
	let fundraiser = $state<Fundraiser | null>(null);
	let totals = $state<FundraiserTotals | null>(null);
	let totalsFailed = $state(false);
	let createOpen = $state(false);

	async function load() {
		loading = true;
		totalsFailed = false;
		try {
			fundraiser = runId
				? await fetchFundraiserForRun(runId)
				: eventId
					? await fetchFundraiserForEvent(eventId)
					: null;
		} catch (e) {
			// A transient load failure must NOT hide the owner's "Create
			// fundraiser" CTA. Leaving fundraiser null falls through to the
			// owner-CTA branch (and renders nothing for a non-owner) rather
			// than sticking on loading and hiding the whole section.
			console.warn('fundraiser load failed', e);
			fundraiser = null;
		}
		// Read separately: a totals failure must not erase a campaign that
		// loaded, and it must not be shown as "0 raised" either.
		if (fundraiser) {
			try {
				totals = await fetchFundraiserTotals(fundraiser.id);
			} catch (e) {
				console.warn('fundraiser totals load failed', e);
				totals = null;
				totalsFailed = true;
			}
		} else {
			totals = null;
		}
		loading = false;
	}

	onMount(() => {
		if (fundraisingOn) load();
	});

	function onCreated(f: Fundraiser) {
		fundraiser = f;
		createOpen = false;
		load();
	}
</script>

{#if fundraisingOn && !loading}
	{#if fundraiser}
		<section class="section fundraiser-section">
			<FundraiserCard {fundraiser} {totals} {totalsFailed} />
			<a class="view-link" href={`/fundraisers/${fundraiser.id}`}>{m('fundraiser.feedTitle')}</a>
		</section>
	{:else if isOwner}
		<section class="section fundraiser-section">
			<button
				type="button"
				class="btn btn-secondary"
				onclick={() => (createOpen = true)}
				data-testid="fundraiser-create-cta"
			>
				{m('fundraiser.createCta')}
			</button>
		</section>

		<Modal open={createOpen} onclose={() => (createOpen = false)} title={m('fundraiser.createCta')}>
			<FundraiserEditor {runId} {eventId} oncreated={onCreated} oncancel={() => (createOpen = false)} />
		</Modal>
	{/if}
{/if}

<style>
	.fundraiser-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
	}
	.view-link {
		font-size: 0.9rem;
	}
</style>
