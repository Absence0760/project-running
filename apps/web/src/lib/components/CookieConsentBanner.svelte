<script lang="ts">
	import { onMount } from 'svelte';
	import { consent } from '$lib/settings/consent.svelte';
	import { m } from '$lib/i18n/store.svelte';

	// `mounted` gates the banner so it's NEVER in the prerendered HTML.
	// Without this, the static build ships with `consent.pending = true`
	// (no localStorage available at prerender time), the browser parses
	// the HTML and shows the banner instantly, then the hydration tick
	// re-reads localStorage and hides it — a visible flash for every
	// returning user. Cost of this gate: a single tick of delay before
	// the banner appears for genuine first-time visitors.
	let mounted = $state(false);
	let dismissed = $state(false);
	onMount(() => {
		mounted = true;

		// Persona-hunt Round 3 finding Privacy #4. Honour the Global
		// Privacy Control signal (navigator.globalPrivacyControl is
		// the client-side mirror of the Sec-GPC: 1 request header;
		// browsers that ship one ship the other). California AG +
		// Colorado AG have ruled GPC is a binding "Do Not Sell /
		// Share" signal under CCPA/CPRA + CPA; EDPB treats it as an
		// objection under GDPR Art 21. A user who has flipped their
		// browser-level toggle has already opted out — surfacing a
		// banner asking them again would be (a) annoying and (b)
		// non-compliant, since the implicit "Reject" via GPC must
		// be persisted just like an explicit click. Auto-persist as
		// `rejected` so future loads + the server-side gate see a
		// consistent state.
		if (consent.pending && hasGpcSignal()) {
			consent.set('rejected');
			dismissed = true;
		}
	});

	function hasGpcSignal(): boolean {
		// `globalPrivacyControl` is non-standard but widely supported
		// (Firefox 100+, Brave, DuckDuckGo, iOS Safari Privacy
		// Protections). Treat undefined as "no signal" — the banner
		// then runs its normal pending → click path.
		try {
			return (
				typeof navigator !== 'undefined' &&
				(navigator as Navigator & { globalPrivacyControl?: boolean })
					.globalPrivacyControl === true
			);
		} catch {
			return false;
		}
	}

	// Single accept/reject rather than per-purpose toggles is deliberate:
	// today there is exactly one consent-gated purpose — third-party
	// services (MapTiler tiles on anon surfaces, Sentry) all ride this one
	// choice. A granular CNIL/ICO-style per-purpose UI is only required
	// once a second, independently-rejectable vendor exists; add the
	// toggles then (audit/cookie-consent). Until then one binary choice
	// maps 1:1 to the one purpose, so per-purpose granularity would be
	// theatre.
	function accept() {
		consent.set('accepted');
		dismissed = true;
		window.location.reload();
	}

	function reject() {
		consent.set('rejected');
		dismissed = true;
	}
</script>

{#if mounted && consent.pending && !dismissed}
	<div class="banner" role="dialog" aria-modal="false" aria-labelledby="cookie-title" aria-describedby="cookie-desc">
		<div class="copy">
			<strong id="cookie-title">{m('cookieConsent.title')}</strong>
			<p id="cookie-desc">
				{m('cookieConsent.descPrefix')} <a href="https://sentry.io/legal/dpa/" target="_blank" rel="noopener noreferrer">Sentry</a>
				{m('cookieConsent.descSuffix')}
				<a href="/cookie-notice">{m('cookieConsent.learnMore')}</a>.
			</p>
		</div>
		<div class="actions">
			<button type="button" class="btn btn-outline" onclick={reject}>{m('cookieConsent.reject')}</button>
			<button type="button" class="btn btn-primary" onclick={accept}>{m('cookieConsent.accept')}</button>
		</div>
	</div>
{/if}

<style>
	/* Compact bottom-right card. The previous full-width centered banner
	   collided with bottom-of-screen action UI (the /runs bulk-bar, the
	   /runs/new Save button) and silently intercepted pointer events
	   wherever it covered. A 24rem corner card keeps the centered
	   content unobstructed; mobile (<48rem) drops it back to a full-
	   width strip because corner-pinned banners look orphaned on a
	   narrow viewport. */
	.banner {
		position: fixed;
		inset-block-end: var(--space-md);
		inset-inline-end: var(--space-md);
		width: min(24rem, calc(100vw - 2 * var(--space-md)));
		background: var(--color-surface);
		color: var(--color-text);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md);
		box-shadow: var(--shadow-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		z-index: var(--z-cookie);
	}
	.copy strong {
		display: block;
		font-size: 0.95rem;
		margin-bottom: var(--space-2xs);
	}
	.copy p {
		margin: 0;
		font-size: 0.85rem;
		line-height: 1.45;
		color: var(--color-text-secondary);
	}
	.actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: flex-end;
	}
	@media (max-width: 48rem) {
		.banner {
			inset-inline-start: var(--space-md);
			width: auto;
		}
	}

	/* When a modal is open the cookie banner steps aside. The previous
	   geometry put the corner-pinned banner over the modal Save button
	   at common viewport widths (1280-1440px), making the PlanMetaEditor
	   Save click flake. Modals are the more time-sensitive surface; the
	   banner reappears the moment the modal closes. */
	:global(body:has(.modal-backdrop)) .banner {
		display: none;
	}
</style>
