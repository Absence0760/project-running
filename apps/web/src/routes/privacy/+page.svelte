<script lang="ts">
	const lastUpdated = '2026-05-15';
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
		<strong>Controller:</strong> Threkir, operated by <em>TODO: legal entity name + address</em>.
		<br />
		<strong>Privacy contact:</strong> <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>.
		<br />
		<strong>EU representative (Art 27 GDPR):</strong> <em>TODO: name + address of the appointed representative</em>. See
		<a href="/docs/compliance/eu-representative">eu-representative.md</a> in the project repo for
		context.
		<br />
		<strong>UK representative (Art 27 UK GDPR):</strong> <em>TODO if offering services to UK residents</em>.
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
		Our service relies on a small set of vetted sub-processors. The current list and what data
		each receives is documented in the project repository at
		<a
			href="https://github.com/Absence0760/project-running/blob/main/docs/compliance/sub-processors.md"
			target="_blank"
			rel="noopener noreferrer">docs/compliance/sub-processors.md</a
		>. Headline relationships:
	</p>
	<ul>
		<li><strong>Supabase</strong> — database, authentication, file storage.</li>
		<li><strong>Amazon Web Services</strong> — web hosting (S3, CloudFront, Lambda).</li>
		<li><strong>Fly.io</strong> — background workers + the live spectator hub.</li>
		<li><strong>Anthropic</strong> (or, on fallback, OpenAI) — AI Coach.</li>
		<li><strong>MapTiler</strong> — map tiles.</li>
		<li><strong>Sentry</strong> — error monitoring.</li>
		<li><strong>RevenueCat + Stripe / Apple IAP / Google Play Billing</strong> — subscriptions.</li>
		<li><strong>Strava / parkrun / Garmin Connect / Health Connect / HealthKit</strong> — only when you connect them.</li>
	</ul>
	<p>
		We notify you of new sub-processors via in-app banner and the public
		<a
			href="https://github.com/Absence0760/project-running/blob/main/docs/compliance/sub-processor-changelog.md"
			target="_blank"
			rel="noopener noreferrer">sub-processor changelog</a
		>
		at least 30 days before they go live. You may withdraw consent and delete your account if you
		object.
	</p>

	<h2>5. International transfers</h2>
	<p>
		Several sub-processors are based in the United States. We rely on the <strong>EU-US Data
		Privacy Framework</strong> certifications where available, plus the European Commission's
		<strong>Standard Contractual Clauses</strong> (2021) for everything else. The DPA for each
		provider is linked from
		<a
			href="https://github.com/Absence0760/project-running/blob/main/docs/compliance/sub-processors.md"
			target="_blank"
			rel="noopener noreferrer">docs/compliance/sub-processors.md</a
		>.
	</p>

	<h2>6. How long we keep it</h2>
	<p>
		Retention is per data category. Highlights:
	</p>
	<ul>
		<li><strong>Account, runs, routes</strong>: until you delete the account.</li>
		<li><strong>Live spectator pings</strong>: 24 hours after the run ends.</li>
		<li><strong>Coach chat history</strong>: 18 months from the message timestamp.</li>
		<li><strong>Notifications</strong>: 90 days from creation.</li>
		<li><strong>Push tokens (FCM / APNs)</strong>: 60 days of inactivity (`last_seen_at`).</li>
		<li><strong>Background-job records</strong>: 30 days after completion (terminal state).</li>
		<li><strong>Rate-limit counters</strong>: 24 hours from the window start.</li>
		<li><strong>Sentry events</strong>: 90 days (Sentry's default).</li>
		<li><strong>AWS Lambda CloudWatch logs</strong>: 30 days (CloudFront access logging is not collected).</li>
		<li><strong>Backups</strong>: a deleted account may persist in encrypted point-in-time-recovery backups for up to 28 days before they roll off.</li>
	</ul>
	<p>
		Full table at
		<a
			href="https://github.com/Absence0760/project-running/blob/main/docs/compliance/retention.md"
			target="_blank"
			rel="noopener noreferrer">docs/compliance/retention.md</a
		>.
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
		Threkir is not directed to children under 13. We require all users to confirm they are
		16 or older at signup; that age is the most conservative threshold across EU member states
		(GDPR Art 8). If you believe a child under 13 has provided personal data to us, please email
		<a href="mailto:privacy@threkir.com">privacy@threkir.com</a> and we will delete the
		account.
	</p>

	<h2>9. Cookies + similar technologies</h2>
	<p>
		See the dedicated <a href="/cookie-notice">Cookie Notice</a>.
	</p>

	<h2>10. Security</h2>
	<p>
		We use TLS in transit, AWS KMS for at-rest secrets, Postgres Row-Level Security to gate
		every database read, and signed-URL controls on storage. Full architecture in the project
		repository under <em>docs/architecture.md</em> and <em>docs/api_database.md</em>.
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
		<br />Postal: <em>TODO: legal address</em>
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
		background: var(--color-bg-elev-1);
		font-weight: 600;
	}
</style>
