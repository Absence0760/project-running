<script lang="ts">
	const lastUpdated = '2026-05-15';
</script>

<svelte:head>
	<title>Terms of Service — Threkir</title>
	<meta name="description" content="Terms of Service for the Threkir running app." />
</svelte:head>

<div class="legal-page">
	<div class="draft-banner">
		<strong>Draft.</strong> This Terms of Service is published as a placeholder so app-store
		reviewers can find it at a stable URL. The legal text below is a working scaffold. It has
		<em>not</em> been reviewed by counsel and is not yet operative.
	</div>

	<h1>Terms of Service</h1>
	<p class="lead">By creating an account or using the Threkir apps, you agree to these terms.</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Who provides the service</h2>
	<p>
		Threkir is operated by <em>TODO: legal entity name + jurisdiction</em>. We provide web,
		mobile, and watch applications for recording runs, planning training, and sharing activity
		with friends and clubs.
	</p>

	<h2>2. Your account</h2>
	<ul>
		<li>You must be at least 16 years old to create an account.</li>
		<li>You are responsible for keeping your password secure.</li>
		<li>You agree to provide accurate information.</li>
		<li>You agree not to share your account with anyone else.</li>
	</ul>

	<h2>3. Your content</h2>
	<p>
		Runs you record, routes you build, photos you upload, and posts you make remain yours. You
		grant us a limited licence to host, display, and process your content as needed to run the
		service. We do not sell your data and do not use it for advertising.
	</p>
	<p>
		When you mark a run or route as public, or share it with a club, you grant us permission to
		display that content to other users.
	</p>

	<h2>4. Subscriptions + payments</h2>
	<ul>
		<li>
			Threkir is free to start. A paid "Pro" tier unlocks the AI Coach (with a daily
			message cap), advanced training-load views, and other features listed on the
			<a href="/compare">/compare</a> page.
		</li>
		<li>
			Payments on the web go through Stripe; on iOS through Apple In-App Purchase; on Android
			through Google Play Billing. We do not see your card details — they go directly to the
			payment processor.
		</li>
		<li>
			<strong>Auto-renewal.</strong> Pro subscriptions renew automatically at the end of each
			period unless you cancel before the renewal date. You can manage and cancel from your
			device's subscription settings (iOS / Android) or your Stripe customer portal (web).
		</li>
		<li>
			<strong>Cancellation is at least as easy as signup.</strong> The "Manage subscription"
			link is in Settings → Pro / Upgrade.
		</li>
		<li>
			<strong>Refunds.</strong> For purchases made through Apple or Google, refunds are handled
			by them under their store policies. For purchases made directly through Stripe, EU and
			UK consumers have a 14-day right of withdrawal (EU Consumer Rights Directive 2011/83/EU
			Art 16(m) — note that we may legitimately ask you to waive this right if you begin
			actively using the Pro AI Coach during the 14-day window). Contact
			<a href="mailto:billing@threkir.com">billing@threkir.com</a> with any refund
			request.
		</li>
	</ul>

	<h2>5. Acceptable use</h2>
	<p>You agree not to:</p>
	<ul>
		<li>Reverse-engineer the service or extract data via automated means without our written permission.</li>
		<li>Upload content that infringes someone else's rights, including GPS tracks that belong to others.</li>
		<li>Harass other users, post unlawful content, or attempt to impersonate anyone.</li>
		<li>Use the service to commit fraud, send spam, or distribute malware.</li>
		<li>Attempt to access another user's account or private data.</li>
	</ul>

	<h2>6. Disclaimers</h2>
	<p>
		Threkir is provided "as is". Training advice and AI Coach responses are informational
		only and do not constitute medical advice. Consult a qualified healthcare professional
		before starting a new training program. Real-time spectator tracking depends on your phone's
		network and battery state and may be delayed or absent without warning.
	</p>
	<p>
		To the maximum extent permitted by law, we disclaim implied warranties of merchantability,
		fitness for a particular purpose, and non-infringement. Nothing in these terms limits or
		excludes our liability for matters that, under your local law, cannot be limited or excluded
		— including death or personal injury caused by our negligence and, in the UK, statutory
		consumer-protection rights.
	</p>

	<h2>7. Liability cap</h2>
	<p>
		To the extent permitted by law, our total liability to you for any claim arising from your
		use of the service is limited to the greater of (a) the amount you paid us in the 12 months
		preceding the event giving rise to the claim and (b) US$50. This cap does not apply where
		applicable law prohibits a cap on our liability.
	</p>

	<h2>8. Termination</h2>
	<p>
		You may close your account at any time from Settings → Delete account. We may suspend or
		terminate accounts that violate these terms, with notice except where notice would not be
		practical (for example, security incidents).
	</p>
	<p>
		When your account is closed, we delete your personal data on the schedule in the
		<a href="/privacy">Privacy Policy</a>.
	</p>

	<h2>9. Changes</h2>
	<p>
		We may update these terms from time to time. Material changes will be announced in-app and
		by email at least 30 days before they take effect. Continued use after that constitutes
		acceptance.
	</p>

	<h2>10. Governing law + venue</h2>
	<p>
		These terms are governed by the laws of <em>TODO: jurisdiction</em>. Disputes will be
		resolved in the courts of <em>TODO: jurisdiction</em>. Nothing here affects mandatory
		consumer-protection rights in your country of residence.
	</p>

	<h2>11. Contact</h2>
	<p>
		General: <a href="mailto:hello@threkir.com">hello@threkir.com</a>
		<br />Billing: <a href="mailto:billing@threkir.com">billing@threkir.com</a>
		<br />Privacy: <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>
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
</style>
