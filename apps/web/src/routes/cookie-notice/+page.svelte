<script lang="ts">
	import { consent } from '$lib/settings/consent.svelte';

	const lastUpdated = '2026-07-14';

	// audit/cookie-consent (May 2026): the prior page told users to
	// use a "Cookie settings" link in the footer that does not exist.
	// Per GDPR Art 7(3) withdrawal must be as easy as giving consent;
	// the button below clears the choice and reloads so the banner
	// re-renders.
	function resetConsent() {
		consent.reset();
		// Full reload so the consent banner re-mounts in its first-
		// visit state (the runes-based store is already updated, but
		// the banner gate fires once at $effect time).
		if (typeof location !== 'undefined') location.reload();
	}
</script>

<svelte:head>
	<title>Cookie Notice — Threkir</title>
	<meta name="description" content="What cookies and similar technologies Threkir uses and why." />
</svelte:head>

<div class="legal-page">
	<h1>Cookie Notice</h1>
	<p class="lead">
		Threkir uses a small number of cookies and similar technologies (including browser
		localStorage). Most are strictly necessary or first-party preferences that never leave your
		device; the consent-gated third-party services are off by default and load only after you opt
		in.
	</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Strictly necessary</h2>
	<p>
		These load unconditionally because the site cannot function (or function securely) without
		them. They do not require consent under EU ePrivacy.
	</p>
	<table>
		<thead>
			<tr><th>Name</th><th>Kind</th><th>Purpose</th><th>Lifetime</th></tr>
		</thead>
		<tbody>
			<tr><td>sb-access-token / sb-refresh-token</td><td>Cookie (Supabase Auth)</td><td>Authentication session</td><td>1 hour / 30 days</td></tr>
			<tr><td>cookie_consent</td><td>localStorage + a same-named cookie</td><td>Remembers your consent choice. The cookie mirrors the stored choice so our server can respect it per-request (for example, gating error monitoring) — the server cannot read localStorage.</td><td>12 months</td></tr>
			<tr><td>strava_oauth_state</td><td>Browser storage</td><td>Anti-forgery (CSRF) state while you connect Strava</td><td>During the connect flow</td></tr>
			<tr><td>run_app.device_id</td><td>localStorage</td><td>A random identifier for this browser so per-device settings can differ from your other devices. First-party only; never used for advertising.</td><td>Persistent</td></tr>
		</tbody>
	</table>

	<h2>2. Preferences + on-device caches</h2>
	<p>
		First-party localStorage that holds your own preferences and offline caches. Nothing in this
		table is sent to a third party; entries keyed by user id or date are cleared on sign-out or
		roll off naturally.
	</p>
	<table>
		<thead>
			<tr><th>Name</th><th>Purpose</th><th>Lifetime</th></tr>
		</thead>
		<tbody>
			<tr><td>run_app.theme</td><td>Light/dark mode preference</td><td>Persistent</td></tr>
			<tr><td>sidebar_collapsed</td><td>Sidebar collapse state</td><td>Persistent</td></tr>
			<tr><td>locale</td><td>Language preference</td><td>Persistent</td></tr>
			<tr><td>settings_cache_* (per user/device)</td><td>Offline-first cache of your account settings, plus a pending-changes queue drained when you're back online</td><td>Until sign-out</td></tr>
			<tr><td>runs_filters_v1 / routes_filters_v1</td><td>Your list filters, so they survive navigation</td><td>Persistent</td></tr>
			<tr><td>water_ml_&lt;user&gt;_&lt;date&gt;</td><td>Today's water-tracker total (stays on this device)</td><td>Per day</td></tr>
			<tr><td>Layout keys (panel widths, goal migration)</td><td>Remember resizable-panel positions; migrate legacy locally-stored goals into your account</td><td>Persistent</td></tr>
		</tbody>
	</table>

	<h2>3. Consent-gated</h2>
	<p>These load only after you accept them via the consent banner.</p>
	<table>
		<thead>
			<tr><th>Name</th><th>Provider</th><th>Purpose</th><th>Lifetime</th></tr>
		</thead>
		<tbody>
			<tr><td>sentry-trace, baggage</td><td>Sentry</td><td>Error monitoring + performance traces</td><td>Per-request</td></tr>
		</tbody>
	</table>

	<h2>4. Third-party services that load on-page</h2>
	<p>
		The following third-party services may set their own cookies or log your IP address when the
		page makes a request to them. We disclose them here even though they're not all "cookies" in
		the strict sense:
	</p>
	<ul>
		<li>
			<strong>MapTiler</strong> (EU, with global edge caching) — every map tile fetch logs the
			requesting IP and the map viewport. Map tiles load only after you accept the consent banner;
			on map screens (run detail, route detail, route builder, live spectator) the map renders as
			a "Load map" placeholder until then.
		</li>
		<li>
			<strong>Open-Meteo</strong> (EU) — fires when you build or view a route, to look up
			elevation. The request includes the route's waypoint coordinates (which can include a point
			near your home) and your IP address.
		</li>
		<li>
			<strong>Open Food Facts</strong> (EU) — fires when you search for a food in the nutrition
			log. The request includes only the search text you typed and your IP address; entering
			macros manually avoids it entirely.
		</li>
		<li>
			<strong>Anthropic / OpenAI</strong> — only fires when you open the AI Coach. The
			request includes prompt text + recent training data.
		</li>
		<li>
			<strong>Supabase Storage (signed URLs)</strong> — every track preview or photo fetch
			generates a short-TTL signed URL. The TTL is short enough that the URL is not a
			persistent identifier.
		</li>
	</ul>

	<h2>5. Your choices</h2>
	<p class="manage-consent">
		<button
			type="button"
			class="btn btn-outline"
			onclick={resetConsent}
			data-testid="manage-cookie-preferences"
		>
			Manage cookie preferences
		</button>
		<span class="manage-consent-hint">
			Clears your current choice and re-opens the consent banner. Required by
			GDPR Art 7(3): withdrawing consent must be as easy as giving it.
		</span>
	</p>
	<ul>
		<li>
			<strong>Global Privacy Control (GPC) is honoured.</strong> If your browser sends the
			<code>Sec-GPC: 1</code> signal, we treat it as a binding opt-out — exactly as if you had
			pressed "Reject" on the banner — and the consent-gated services above never load. Under
			the CCPA/CPRA, GPC counts as a valid opt-out of sale/share (we don't sell or share your
			data in any case).
		</li>
		<li>
			<strong>Browser-level "Do Not Track" (DNT)</strong> — the older, distinct signal — is not
			honoured because it has no consistent meaning across browsers. Use GPC or the button above
			instead.
		</li>
		<li>
			<strong>Block cookies in your browser.</strong> Most browsers let you reject cookies
			from a specific site. Strictly-necessary cookies cannot be blocked without breaking
			authentication.
		</li>
	</ul>

	<h2>6. Contact</h2>
	<p>
		Privacy questions: <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>.
	</p>
</div>

<style>
	.legal-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
		line-height: 1.6;
	}
	.manage-consent {
		display: flex;
		flex-direction: column;
		gap: var(--space-sm, 0.5rem);
		margin: var(--space-md, 1rem) 0;
	}
	.manage-consent-hint {
		color: var(--color-muted, #6b7280);
		font-size: 0.9em;
	}
	h1 {
		margin-top: 0;
	}
	h2 {
		margin-top: var(--space-2xl);
		font-size: 1.25rem;
	}
	.lead {
		font-size: 1.1rem;
		color: var(--color-text-secondary);
	}
	.meta {
		color: var(--color-text-tertiary);
		font-size: 0.875rem;
		margin-bottom: var(--space-2xl);
	}
	ul {
		padding-inline-start: 1.25rem;
	}
	li {
		margin-bottom: var(--space-xs);
	}
	table {
		width: 100%;
		border-collapse: collapse;
		margin: var(--space-md) 0;
	}
	th,
	td {
		text-align: start;
		padding: var(--space-xs) var(--space-sm);
		border-bottom: 1px solid var(--color-border);
		vertical-align: top;
	}
	th {
		background: var(--color-surface);
		font-weight: 600;
	}
</style>
