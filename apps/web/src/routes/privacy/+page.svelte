<script lang="ts">
	import { OPERATOR, OPERATOR_FACTS_COMPLETE } from '$lib/legal/operator';

	const lastUpdated = '2026-07-14';
</script>

<svelte:head>
	<title>Privacy Policy — Threkir</title>
	<meta name="description" content="How Threkir collects, uses, and protects your personal data." />
</svelte:head>

<div class="legal-page">
	{#if !OPERATOR_FACTS_COMPLETE}
		<div class="pending-banner" data-testid="operator-facts-pending">
			A small number of operator details are still being finalised: our registered postal address,
			the EU and UK representative appointments, and the governing-law state. Each pending item is
			marked below. Until they are published here, direct any matter that would otherwise go to
			them to <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>.
		</div>
	{/if}

	<h1>Privacy Policy</h1>
	<p class="lead">
		Threkir is a running, training, and fitness app. This policy explains what data we collect,
		why, who we share it with, how long we keep it, and how to exercise your rights.
	</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Who we are</h2>
	<p>
		<strong>Controller:</strong> {OPERATOR.serviceName}, operated by {OPERATOR.controllerDescription}.
		<br />
		<strong>Postal address:</strong>
		{#if OPERATOR.postalAddress}{OPERATOR.postalAddress}{:else}<em>pending publication — write to
			<a href="mailto:privacy@threkir.com">privacy@threkir.com</a> in the meantime</em>{/if}
		<br />
		<strong>Privacy contact:</strong> <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>.
		We have not appointed a Data Protection Officer; we are not required to, and the privacy
		contact above reaches the controller directly.
		<br />
		<strong>EU representative (Art 27 GDPR):</strong>
		{#if OPERATOR.euRepresentative}{OPERATOR.euRepresentative.name}, {OPERATOR.euRepresentative
				.address} (<a href="mailto:{OPERATOR.euRepresentative.email}"
				>{OPERATOR.euRepresentative.email}</a
			>){:else}<em>appointment in progress; until published here, EU residents and supervisory
			authorities may contact <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>
			directly</em>{/if}
		<br />
		<strong>UK representative (Art 27 UK GDPR):</strong>
		{#if OPERATOR.ukRepresentative}{OPERATOR.ukRepresentative.name}, {OPERATOR.ukRepresentative
				.address} (<a href="mailto:{OPERATOR.ukRepresentative.email}"
				>{OPERATOR.ukRepresentative.email}</a
			>){:else}<em>appointment in progress; until published here, UK residents and the ICO may
			contact <a href="mailto:privacy@threkir.com">privacy@threkir.com</a> directly</em>{/if}
	</p>

	<h2>2. What data we collect</h2>
	<ul>
		<li>
			<strong>Account</strong>: email address, optional display name, optional profile photo,
			optional gender and date of birth (used for tiered leaderboards and age-graded results).
		</li>
		<li>
			<strong>Activity</strong>: GPS tracks, distance, duration, pace, elevation, heart rate
			(when paired with a sensor or imported from a third-party app), step count, activity type,
			and activity photos you upload.
		</li>
		<li>
			<strong>Health and body data (with your explicit consent)</strong>: height, body-weight
			entries, activity level, nutrition targets, food-log entries, and hydration amounts. Gym
			workouts (exercises, sets, reps, weights) are also stored. Heart rate and health imports
			fall under the same explicit-consent gate.
		</li>
		<li>
			<strong>Race checkpoint data</strong>: if you take part in an organised event that uses our
			race-director tools, aid-station staff may record your bib crossings (in/out times) and —
			at events that run medical weigh-ins — your body weight and any medical hold or note. The
			weigh-in and medical fields are special-category health data; they are scrubbed after 90
			days (the split times are your race result and are kept like any other result).
		</li>
		<li>
			<strong>Privacy zones</strong>: the coordinates of areas you designate (for example around
			your home) so that your tracks can be clipped before anyone else sees them. These
			coordinates exist to protect you and are never shown to other users.
		</li>
		<li>
			<strong>Live location</strong>: if you turn on live spectator tracking, real-time location
			pings during the run, kept for 48 hours (see section 7).
		</li>
		<li>
			<strong>Social</strong>: kudos, comments, photos, clubs you join, people you follow, event
			RSVPs, direct messages you exchange with other users, and any blocks or reports you file.
		</li>
		<li>
			<strong>Safety contacts</strong>: email addresses of people you nominate for safety
			features. If you add someone else's address, make sure you have their agreement.
		</li>
		<li>
			<strong>AI Coach</strong>: every chat message you send. We pass each prompt to our AI
			provider together with a summary of your recent training to generate a useful response.
		</li>
		<li>
			<strong>Subscription</strong>: subscription tier and renewal state (we do not see or store
			card numbers — that data goes directly to Stripe / Apple / Google).
		</li>
		<li>
			<strong>Paid events and fundraising</strong>: if you register for a paid event or donate to
			a fundraiser, your order state and, for donations, the display name and message you choose
			to show. If you host paid events, we store only your Stripe account identifier — your
			banking and identity documents go directly to Stripe.
		</li>
		<li>
			<strong>Device + network</strong>: device type, app version, IP address (truncated for
			analytics), error logs, and — if you enable notifications — a push token.
		</li>
		<li>
			<strong>Third-party imports</strong>: when you connect Strava, parkrun, Garmin, Health
			Connect, or HealthKit, we receive the activity data they publish to us.
		</li>
	</ul>

	<h2>3. Why we process it (lawful basis)</h2>
	<table>
		<thead>
			<tr><th>Purpose</th><th>Lawful basis</th></tr>
		</thead>
		<tbody>
			<tr><td>Provide the core service (record runs, sync across devices, social features)</td><td>Contract — Art 6(1)(b) GDPR</td></tr>
			<tr><td>Heart rate, health imports, body metrics, nutrition and food logs, checkpoint medical weigh-ins</td><td>Explicit consent for special-category data — Art 9(2)(a) GDPR</td></tr>
			<tr><td>AI Coach</td><td>Consent — Art 6(1)(a) GDPR</td></tr>
			<tr><td>Paid event registration, fundraising donations, Pro subscription billing</td><td>Contract — Art 6(1)(b) GDPR</td></tr>
			<tr><td>Marketing email (only if opted in)</td><td>Consent</td></tr>
			<tr><td>Error monitoring, abuse prevention, moderation of reported content</td><td>Legitimate interest — Art 6(1)(f) GDPR</td></tr>
			<tr><td>Comply with a subpoena, court order, or store demand</td><td>Legal obligation — Art 6(1)(c) GDPR</td></tr>
		</tbody>
	</table>
	<p>
		Where processing rests on consent you can withdraw it at any time (section 8) without
		affecting the lawfulness of prior processing.
	</p>

	<h2>4. Automated decision-making</h2>
	<p>
		We do not make decisions about you that produce legal or similarly significant effects based
		solely on automated processing (Art 22 GDPR). The AI Coach and the training-plan generator
		produce suggestions only — nothing they output changes your access to the service, your
		pricing, or your account standing, and you are free to ignore them.
	</p>

	<h2 id="sub-processors">5. Who we share with (sub-processors)</h2>
	<p>
		Our service relies on a small set of vetted sub-processors. Each receives only the data it
		needs for its purpose. The current list — what each is for, and what it receives:
	</p>
	<ul>
		<li>
			<strong>Supabase</strong> (hosted in eu-west-2, London) — database, authentication, file
			storage, and the transactional auth emails (signup confirmation, password reset). Holds all
			account, activity (including GPS tracks and health-related fields), and social data.
		</li>
		<li>
			<strong>Amazon Web Services</strong> — web hosting (S3, CloudFront, Lambda, KMS, Route 53).
			Serves the web bundle and holds data-export Storage objects and server logs.
		</li>
		<li>
			<strong>Fly.io</strong> (London) — background workers, route processing, and the live
			spectator hub. Your run tracks transit through map-matching and route-generation jobs. The
			routing engines themselves (OSRM, GraphHopper, and our own loop-search service) are
			self-hosted on this infrastructure — no third party beyond Fly.io is involved.
		</li>
		<li>
			<strong>Upstash Redis</strong> — an optional cache for the live spectator hub. When our
			deployment uses it, it briefly holds live-run ping coordinates keyed by run id, expiring on
			the same 48-hour window as our own store. When not enabled, live pings never leave our own
			infrastructure.
		</li>
		<li>
			<strong>Anthropic</strong> (or, on fallback, OpenAI) — AI Coach. Receives your chat prompt
			plus a summary of your recent training (which can include heart-rate and goal data). We use
			the provider's commercial API: your prompts and the responses are <strong>not used to train
			the provider's models</strong>, and under Anthropic's default API retention policy inputs and
			outputs are deleted from Anthropic's systems within 30 days of processing (material flagged
			by automated trust-and-safety screening can be retained longer). Your chat history itself is
			stored by us, not the provider — see section 7.
		</li>
		<li>
			<strong>MapTiler</strong> (EU, with global edge caching) — map tiles. Receives the map
			viewport and your IP address on each tile request; loads only after you accept the cookie
			banner.
		</li>
		<li>
			<strong>Open-Meteo</strong> (EU) — elevation lookup when you build or view a route. Receives
			the route's waypoint coordinates (which can include a point near your home) and your IP
			address.
		</li>
		<li>
			<strong>Open Food Facts</strong> (EU, a French non-profit) — nutrition food search. Receives
			only the search text you type (for example "rolled oats") and your IP address; no account
			identifier, no body data. Skipping search and entering macros manually avoids it entirely.
		</li>
		<li>
			<strong>Sentry</strong> — error monitoring. Receives a pseudonymous user id, URL paths, and
			redacted error traces.
		</li>
		<li>
			<strong>RevenueCat + Stripe + Apple IAP + Google Play Billing</strong> — subscription
			billing. Receive your subscription tier and payment tokens; card numbers never reach us.
		</li>
		<li>
			<strong>Stripe Connect</strong> (marketplace — distinct from the subscription billing above)
			— paid event registration and fundraiser donations. Your email, payment, and any display
			name or message you add are sent to a Checkout Session tied to the event host's or
			fundraiser owner's <em>own</em> connected Stripe account, so that recipient — not Threkir —
			becomes a custodian of that contact data.
		</li>
		<li>
			<strong>Email delivery</strong> (Resend or AWS SES — provider selection pending) —
			transactional and digest email beyond the Supabase auth mail above. Receives your email
			address, name, and the message content (receipts, lifecycle and safety mail, the weekly
			digest).
		</li>
		<li>
			<strong>Google Sign-In</strong> — identity, only when you choose "Sign in with Google".
			Validates an ID token and returns your email and name to us. This is a separate flow from
			Google Play Billing above.
		</li>
		<li>
			<strong>Google FCM</strong> and <strong>Apple APNs</strong> — push-notification delivery,
			only when you enable notifications. Receive your device push token and the notification title
			and body.
		</li>
		<li>
			<strong>RunSignUp / ChronoTrack / UltraSignup</strong> — race-result import, only when you
			import or link a race. We may send an optional race-platform user id and receive finisher
			results (names, bib numbers, times).
		</li>
		<li>
			<strong>Strava / parkrun / Garmin Connect / Health Connect / HealthKit</strong> — only when
			you connect them. Receive OAuth tokens; return the activity data they publish to us.
		</li>
	</ul>
	<p>
		Our server-side error monitoring (Sentry) captures crash and exception reports from our
		Edge Functions. Because it runs on the server it cannot consult your in-app telemetry
		choice, so it operates on a <strong>legitimate-interest</strong> basis (Art 6(1)(f)) with
		data minimisation: it sends no default personal identifiers and strips request bodies and
		headers before transmission. Client-side error monitoring remains gated on your telemetry
		consent.
	</p>
	<p>
		We give at least 30 days' notice before a new sub-processor goes live. The canonical
		disclosure is our maintained
		<a
			href="https://github.com/Absence0760/project-running/blob/main/docs/compliance/sub-processor-changelog.md"
			target="_blank"
			rel="noopener noreferrer">sub-processor changelog</a
		>; registered users are additionally notified by email (and, where available, in-app). You may
		object by emailing the privacy contact above, or withdraw consent and delete your account.
	</p>

	<h2>6. International transfers</h2>
	<p>
		Your core data has an EU home: <strong>Supabase</strong> — our primary database, authentication
		and file store, which holds your GPS tracks, health-related fields, and account data — is
		hosted in <strong>eu-west-2 (London)</strong>. Our background workers and live-spectator hub
		(<strong>Fly.io</strong>) also run in London, and <strong>MapTiler</strong>,
		<strong>Open-Meteo</strong>, and <strong>Open Food Facts</strong> serve from the EU (with
		global edge caching for map tiles).
	</p>
	<p>
		Several other sub-processors are based in the United States (for example AWS compute,
		Anthropic, Stripe, RevenueCat, and Sentry). For those transfers we rely on the <strong
			>EU-US Data Privacy Framework</strong
		>
		certifications where available, plus the European Commission's
		<strong>Standard Contractual Clauses</strong> (2021) for everything else. The data-processing
		agreement for each provider is held on file; email <a href="mailto:privacy@threkir.com"
			>privacy@threkir.com</a
		> to request the details for a specific sub-processor.
	</p>

	<h2>7. How long we keep it</h2>
	<ul>
		<li><strong>Account, runs, routes, gym workouts, food logs, body metrics</strong>: until you delete the item or the account.</li>
		<li><strong>Live spectator pings</strong>: 48 hours (both our database and, when enabled, the Upstash cache).</li>
		<li><strong>Race spectator pings</strong> (organised-event live results): 48 hours.</li>
		<li><strong>Checkpoint medical weigh-in fields</strong> (weight, medical hold/note): scrubbed 90 days after they were recorded; the in/out split times are race results and are kept.</li>
		<li><strong>Direct messages</strong>: 2 years from sending, or immediately when either party deletes their account.</li>
		<li><strong>Coach chat history</strong>: 18 months from the message timestamp.</li>
		<li><strong>AI-provider copies of coach prompts</strong>: deleted by the provider within 30 days of processing (Anthropic API default retention); never used for model training.</li>
		<li><strong>Coach usage counters</strong> (per-day message counts): 7 days.</li>
		<li><strong>Notifications</strong>: 90 days from creation.</li>
		<li><strong>Push tokens (FCM / APNs)</strong>: 60 days of inactivity.</li>
		<li><strong>Payout account link (event hosts / fundraiser owners)</strong>: until account deletion, at which point we also close the connected Stripe account (Stripe retains transaction records under its own legal obligations).</li>
		<li><strong>Background-job records</strong>: 30 days after completion.</li>
		<li><strong>Rate-limit counters</strong>: 24 hours from the window start.</li>
		<li><strong>Sentry events</strong>: 90 days (Sentry's default).</li>
		<li><strong>AWS Lambda CloudWatch logs</strong>: 30 days (CloudFront access logging is not collected).</li>
		<li><strong>Backups</strong>: a deleted account may persist in encrypted point-in-time-recovery backups for up to 28 days before they roll off.</li>
	</ul>
	<p>
		The categories above are our retention schedule. Where a period is not listed, we keep the
		data only as long as needed for the purpose it was collected, then delete or anonymise it.
	</p>

	<h2>8. Your rights</h2>
	<p>Under the GDPR / UK GDPR / CCPA / LGPD you have the right to:</p>
	<ul>
		<li><strong>Access</strong> your personal data (Art 15) — use Settings → Export your data.</li>
		<li><strong>Rectify</strong> inaccurate data (Art 16) — use Settings → Profile.</li>
		<li><strong>Erase</strong> your data (Art 17) — use Settings → Delete account. Deletion cascades through our database, drains your uploaded files from storage, and disconnects or deletes linked third-party resources (for example Strava authorisation and any connected Stripe account).</li>
		<li><strong>Restrict</strong> or <strong>object to</strong> processing (Arts 18 + 21) — email <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>. There is no self-service toggle yet; we action these manually and confirm within one month.</li>
		<li><strong>Portability</strong> (Art 20) — use Settings → Export your data; the bundle is machine-readable JSON plus GPX.</li>
		<li><strong>Withdraw consent</strong> at any time without affecting the lawfulness of prior processing. AI Coach consent and health-data consent are each withdrawable self-service in Settings → Account; withdrawing blocks the corresponding processing immediately.</li>
		<li><strong>Object to direct marketing</strong> at any time (Art 21(2)) — every marketing email carries an unsubscribe link, and the email preference is in Settings. Transactional mail (receipts, security notices) is not marketing.</li>
		<li><strong>Lodge a complaint</strong> with your local supervisory authority. UK residents may contact the <a href="https://ico.org.uk/" target="_blank" rel="noopener noreferrer">ICO</a>; EU residents the DPA of their member state; Brazilian residents the ANPD; Canadian residents the OPC (Quebec: the CAI); Australian residents the OAIC.</li>
	</ul>
	<p>
		For the purposes of Canadian law (including Quebec's Law 25), the privacy contact above is
		our designated person in charge of the protection of personal information.
	</p>
	<p>
		When you exercise a right by email, we verify the request by matching (or confirming a link
		sent to) the email address on the account. An authorised agent may act for you where local law
		provides for it, subject to the same verification.
	</p>
	<p>
		<strong>For California residents (CCPA/CPRA):</strong> we do not sell your personal
		information, and we do not share it for cross-context behavioural advertising. We honour the
		<strong>Global Privacy Control</strong> signal: a browser sending GPC is treated as a binding
		opt-out and the consent-gated services never load. The rights to know, delete, and correct are
		served by the same self-service tools listed above, and we will never discriminate against you
		for exercising them.
	</p>

	<h2>9. Children</h2>
	<p>
		Threkir requires all users to confirm they are <strong>16 or older</strong> at signup — the
		most conservative age-of-consent threshold across EU member states (GDPR Art 8) — and is not
		directed to anyone under that age (which includes children under 13 for US COPPA purposes). We
		do not knowingly collect personal data from anyone under 16. If you believe someone under 16
		has provided personal data to us, please email
		<a href="mailto:privacy@threkir.com">privacy@threkir.com</a> and we will delete the account.
	</p>

	<h2>10. Related notices</h2>
	<p>
		Cookies and similar technologies are covered in the dedicated
		<a href="/cookie-notice">Cookie Notice</a>. Washington residents (and residents of other US
		states with consumer-health-data laws) have a dedicated
		<a href="/health-data-notice">Consumer Health Data Privacy Policy</a>.
	</p>

	<h2>11. Security + breach notification</h2>
	<p>
		We use TLS in transit, AWS KMS for at-rest secrets, Postgres Row-Level Security to gate
		every database read, and signed-URL controls on storage. If a personal-data breach occurs
		that risks your rights, we will notify the competent supervisory authority within 72 hours
		(Art 33 GDPR) and, where the risk is high, notify you directly (Art 34).
	</p>
	<p>
		If you discover a vulnerability, please email <a href="mailto:security@threkir.com">security@threkir.com</a>.
	</p>

	<h2>12. Changes</h2>
	<p>
		We will update this policy from time to time. Material changes will be announced via in-app
		notice and email at least 30 days before they take effect.
	</p>

	<h2>13. Contact</h2>
	<p>
		Privacy: <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>
		<br />Security: <a href="mailto:security@threkir.com">security@threkir.com</a>
		<br />Postal: {#if OPERATOR.postalAddress}{OPERATOR.postalAddress}{:else}<em>pending
			publication — use the privacy email above in the meantime</em>{/if}
	</p>
</div>

<style>
	.legal-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
		line-height: 1.6;
	}
	.pending-banner {
		background: var(--color-surface);
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-2xl);
		font-size: 0.9375rem;
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
