<script lang="ts">
	const lastUpdated = '2026-07-02';
</script>

<svelte:head>
	<title>Privacy Policy — Threkir</title>
	<meta name="description" content="How Threkir collects, uses, and protects your personal data." />
</svelte:head>

<div class="legal-page">
	<div class="draft-banner">
		<strong>Draft.</strong> This Privacy Policy is published as a placeholder so app-store
		reviewers can find it at a stable URL. The legal text below is a working scaffold based on the
		GDPR / UK GDPR / CCPA / LGPD baseline. It has <em>not</em> been reviewed by counsel and is not
		yet the operative policy. Do not rely on it; contact us at the address below with any
		question.
	</div>

	<h1>Privacy Policy</h1>
	<p class="lead">
		Threkir is a running app. This policy explains what data we collect, why, who we share it
		with, how long we keep it, and how to exercise your rights.
	</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Who we are</h2>
	<p>
		<strong>Controller:</strong> Threkir, operated by Jared Howard.
		<em>[Legal entity name and registered postal address to be confirmed before EU launch.]</em>
		<br />
		<strong>Privacy contact:</strong> <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>.
		<br />
		<strong>EU representative (Art 27 GDPR):</strong>
		<em
			>[To be appointed before offering services to EU residents — representative name and EU
			establishment address to be confirmed before EU launch.]</em
		>
		<br />
		<strong>UK representative (Art 27 UK GDPR):</strong>
		<em
			>[To be appointed before offering services to UK residents — representative name and UK
			establishment address to be confirmed before UK launch.]</em
		>
	</p>

	<h2>2. What data we collect</h2>
	<ul>
		<li>
			<strong>Account</strong>: email address, optional display name, optional profile photo,
			optional gender + date of birth (used only for tiered leaderboards).
		</li>
		<li>
			<strong>Activity</strong>: GPS tracks, distance, duration, pace, elevation, heart rate
			(when paired with a chest strap or imported from a third-party app), step count, activity
			type.
		</li>
		<li>
			<strong>Social</strong>: kudos, comments, photos, clubs you join, people you follow.
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
			<strong>Device + network</strong>: device type, app version, IP address (truncated for
			analytics), error logs.
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
			<tr><td>Provide the core service (record runs, sync across devices)</td><td>Contract — Art 6(1)(b) GDPR</td></tr>
			<tr><td>Heart rate, gender, date of birth, health imports</td><td>Explicit consent for special-category data — Art 9(2)(a) GDPR</td></tr>
			<tr><td>AI Coach</td><td>Consent — Art 6(1)(a) GDPR</td></tr>
			<tr><td>Marketing email (only if opted in)</td><td>Consent</td></tr>
			<tr><td>Error monitoring + abuse prevention</td><td>Legitimate interest — Art 6(1)(f) GDPR</td></tr>
			<tr><td>Comply with a subpoena, court order, or store demand</td><td>Legal obligation — Art 6(1)(c) GDPR</td></tr>
		</tbody>
	</table>

	<h2>4. Who we share with (sub-processors)</h2>
	<p>
		Our service relies on a small set of vetted sub-processors. Each receives only the data it
		needs for its purpose. The current list — what each is for, and what it receives:
	</p>
	<ul>
		<li>
			<strong>Supabase</strong> (hosted in eu-west-2, London) — database, authentication, file
			storage. Holds all account, activity (including GPS tracks and health-related fields), and
			social data.
		</li>
		<li>
			<strong>Amazon Web Services</strong> — web hosting (S3, CloudFront, Lambda, KMS, Route 53).
			Serves the web bundle and holds data-export Storage objects and server logs.
		</li>
		<li>
			<strong>Fly.io</strong> (London) — background workers, route processing, and the live
			spectator hub. Your run tracks transit through map-matching and route-generation jobs.
		</li>
		<li>
			<strong>Anthropic</strong> (or, on fallback, OpenAI) — AI Coach. Receives your chat prompt
			plus a summary of your recent training (which can include heart-rate and goal data). We use
			the provider's commercial API: your prompts and the responses are <strong>not used to train
			the provider's models</strong>, and under Anthropic's default API retention policy inputs and
			outputs are deleted from Anthropic's systems within 30 days of processing (material flagged
			by automated trust-and-safety screening can be retained longer). Your chat history itself is
			stored by us, not the provider — see section 6.
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
			name or message you add are sent to a Checkout Session tied to the event host's or charity's
			<em>own</em> connected Stripe account, so that recipient — not Threkir — becomes a custodian
			of that contact data.
		</li>
		<li>
			<strong>Email delivery</strong> (Resend or AWS SES — provider selection pending) —
			transactional and digest email. Receives your email address, name, and the message content
			(receipts, lifecycle and safety mail, the weekly digest).
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
		disclosure is our maintained sub-processor list; registered users are additionally notified by
		email (and, where available, in-app). You may object by emailing the privacy contact above, or
		withdraw consent and delete your account.
	</p>

	<h2>5. International transfers</h2>
	<p>
		Your core data has an EU home: <strong>Supabase</strong> — our primary database, authentication
		and file store, which holds your GPS tracks, health-related fields, and account data — is
		hosted in <strong>eu-west-2 (London)</strong>. Our background workers and live-spectator hub
		(<strong>Fly.io</strong>) also run in London, and <strong>MapTiler</strong> and
		<strong>Open-Meteo</strong> serve from the EU (with global edge caching for map tiles).
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

	<h2>6. How long we keep it</h2>
	<p>
		Retention is per data category. Highlights:
	</p>
	<ul>
		<li><strong>Account, runs, routes</strong>: until you delete the account.</li>
		<li><strong>Live spectator pings</strong>: 24 hours after the run ends.</li>
		<li><strong>Coach chat history</strong>: 18 months from the message timestamp.</li>
		<li><strong>AI-provider copies of coach prompts</strong>: deleted by the provider within 30 days of processing (Anthropic API default retention); never used for model training.</li>
		<li><strong>Notifications</strong>: 90 days from creation.</li>
		<li><strong>Push tokens (FCM / APNs)</strong>: 60 days of inactivity (`last_seen_at`).</li>
		<li><strong>Background-job records</strong>: 30 days after completion (terminal state).</li>
		<li><strong>Rate-limit counters</strong>: 24 hours from the window start.</li>
		<li><strong>Sentry events</strong>: 90 days (Sentry's default).</li>
		<li><strong>AWS Lambda CloudWatch logs</strong>: 30 days (CloudFront access logging is not collected).</li>
		<li><strong>Backups</strong>: a deleted account may persist in encrypted point-in-time-recovery backups for up to 28 days before they roll off.</li>
	</ul>
	<p>
		The categories above are our retention schedule. Where a period is not listed, we keep the
		data only as long as needed for the purpose it was collected, then delete or anonymise it.
	</p>

	<h2>7. Your rights</h2>
	<p>Under the GDPR / UK GDPR / CCPA / LGPD you have the right to:</p>
	<ul>
		<li><strong>Access</strong> your personal data (Art 15) — use Settings → Export your data.</li>
		<li><strong>Rectify</strong> inaccurate data (Art 16) — use Settings → Profile.</li>
		<li><strong>Erase</strong> your data (Art 17) — use Settings → Delete account.</li>
		<li><strong>Restrict</strong> or <strong>object to</strong> processing (Arts 18 + 21) — email <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>.</li>
		<li><strong>Portability</strong> (Art 20) — use Settings → Export your data; the bundle is machine-readable JSON.</li>
		<li><strong>Withdraw consent</strong> at any time without affecting the lawfulness of prior processing.</li>
		<li><strong>Lodge a complaint</strong> with your local supervisory authority. UK residents may contact the <a href="https://ico.org.uk/" target="_blank" rel="noopener noreferrer">ICO</a>. EU residents may contact the DPA of their member state.</li>
	</ul>

	<h2>8. Children</h2>
	<p>
		Threkir requires all users to confirm they are <strong>16 or older</strong> at signup — the
		most conservative age-of-consent threshold across EU member states (GDPR Art 8) — and is not
		directed to anyone under that age (which includes children under 13 for US COPPA purposes). We
		do not knowingly collect personal data from anyone under 16. If you believe someone under 16
		has provided personal data to us, please email
		<a href="mailto:privacy@threkir.com">privacy@threkir.com</a> and we will delete the account.
	</p>

	<h2>9. Cookies + similar technologies</h2>
	<p>
		See the dedicated <a href="/cookie-notice">Cookie Notice</a>.
	</p>

	<h2>10. Security</h2>
	<p>
		We use TLS in transit, AWS KMS for at-rest secrets, Postgres Row-Level Security to gate
		every database read, and signed-URL controls on storage. Full architecture in the project
		repository under <em>docs/architecture/architecture.md</em> and <em>docs/backend/api_database.md</em>.
	</p>
	<p>
		If you discover a vulnerability, please email <a href="mailto:security@threkir.com">security@threkir.com</a>.
	</p>

	<h2>11. Changes</h2>
	<p>
		We will update this policy from time to time. Material changes will be announced via in-app
		notice and email at least 30 days before they take effect. The history of changes is in this
		repository's git log.
	</p>

	<h2>12. Contact</h2>
	<p>
		Privacy: <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>
		<br />Security: <a href="mailto:security@threkir.com">security@threkir.com</a>
		<br />Postal: <em>[Registered postal address to be confirmed before EU launch.]</em>
	</p>
</div>

<style>
	.legal-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
		line-height: 1.6;
	}
	.draft-banner {
		background: var(--color-warning-bg, #fff3cd);
		color: var(--color-warning-text, #664d03);
		border: 1px solid var(--color-warning-border, #ffecb5);
		border-radius: var(--radius-md);
		padding: var(--space-md) var(--space-lg);
		margin-bottom: var(--space-2xl);
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
