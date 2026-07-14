<script lang="ts">
	import { OPERATOR, OPERATOR_FACTS_COMPLETE } from '$lib/legal/operator';

	const lastUpdated = '2026-07-14';
</script>

<svelte:head>
	<title>Terms of Service — Threkir</title>
	<meta name="description" content="Terms of Service for the Threkir running app." />
</svelte:head>

<div class="legal-page">
	{#if !OPERATOR_FACTS_COMPLETE}
		<div class="pending-banner" data-testid="operator-facts-pending">
			A small number of operator details are still being finalised: the registered postal address
			and the governing-law state. Each pending item is marked below. Until they are published
			here, direct any related question to
			<a href="mailto:hello@threkir.com">hello@threkir.com</a>.
		</div>
	{/if}

	<h1>Terms of Service</h1>
	<p class="lead">By creating an account or using the Threkir apps, you agree to these terms.</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Who provides the service</h2>
	<p>
		Threkir is operated by {OPERATOR.controllerDescription}. We provide web, mobile, and watch
		applications for recording runs and other activities, planning training, logging gym workouts
		and nutrition, sharing activity with friends and clubs, live spectator tracking, an AI
		training coach, and a marketplace where club event hosts can sell registrations and
		fundraiser owners can collect donations.
	</p>

	<h2>2. Your account</h2>
	<ul>
		<li>You must be at least 16 years old to create an account (see the <a href="/privacy">Privacy Policy</a> for why 16).</li>
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
	<p>
		You can <strong>block</strong> another user from their profile (they can no longer interact
		with you) and <strong>report</strong> a profile, club, route, run, comment, post, or review.
		Reports are reviewed and repeatedly-reported content may be hidden automatically pending
		review. We may remove content that violates these terms. If your content is removed or your
		account is actioned and you believe that was a mistake, email
		<a href="mailto:hello@threkir.com">hello@threkir.com</a> and we will take a second look.
	</p>

	<h2>4. Copyright complaints</h2>
	<p>
		If you believe content on Threkir infringes your copyright, send a notice to
		<a href="mailto:dmca@threkir.com">dmca@threkir.com</a> including: identification of the
		copyrighted work, the URL of the allegedly infringing material, your contact details, a
		statement of good-faith belief that the use is unauthorised, a statement under penalty of
		perjury that your notice is accurate and that you are (or act for) the rights holder, and
		your physical or electronic signature. We will remove or disable access to material we
		determine to be infringing, and terminate repeat infringers. The user who posted the material
		may send a counter-notice with the corresponding statutory elements to the same address.
	</p>

	<h2>5. Pro subscription</h2>
	<ul>
		<li>
			Threkir is free to start. A paid "Pro" tier — currently <strong>US$9.99 per month</strong> —
			unlocks the AI Coach's higher daily message cap, advanced training-load views, AI route
			descriptions, server-side route generation, and the other features listed on the
			<a href="/compare">/compare</a> page. Free accounts include a small daily AI Coach
			allowance; both tiers are capped per day, and the current caps are shown on the compare
			page and in the Coach itself.
		</li>
		<li>
			Payments on the web go through Stripe; on iOS through Apple In-App Purchase; on Android
			through Google Play Billing. We do not see your card details — they go directly to the
			payment processor.
		</li>
		<li>
			<strong>Auto-renewal.</strong> Pro subscriptions renew automatically at the then-current
			price at the end of each period unless you cancel before the renewal date. You can manage
			and cancel from your device's subscription settings (iOS / Android) or your Stripe customer
			portal (web). We will notify you before any price increase takes effect on your renewal.
		</li>
		<li>
			<strong>Cancellation is at least as easy as signup.</strong> The "Manage subscription"
			link is in Settings → Pro / Upgrade. Cancelling stops the next renewal; you keep Pro until
			the end of the paid period.
		</li>
		<li>
			<strong>Refunds.</strong> For purchases made through Apple or Google, refunds are handled
			by them under their store policies. For purchases made directly through Stripe, EU and UK
			consumers have a 14-day right of withdrawal. If you ask us to start providing Pro
			immediately, you can still withdraw within the 14 days and we will refund the amount
			proportionate to the unused part of the period. To withdraw, email
			<a href="mailto:billing@threkir.com">billing@threkir.com</a> — an unequivocal statement is
			enough, and you may (but do not have to) use the EU model withdrawal form. Contact the same
			address with any other refund request.
		</li>
	</ul>

	<h2>6. Paid events, classes, and donations (marketplace)</h2>
	<p>
		Clubs on Threkir can host paid events (for example a class with a per-session fee), and
		users can attach fundraising pages to runs and events. For these transactions
		<strong>Threkir is a platform, not the seller</strong>:
	</p>
	<ul>
		<li>
			<strong>Your contract is with the host.</strong> When you buy an event registration, the
			seller (merchant of record) is the event host — the person teaching the class or organising
			the event — not Threkir. Payment is processed by Stripe into the host's own Stripe account;
			Threkir charges the host a platform fee per transaction. The host, not Threkir, is
			responsible for delivering the event and for its tax obligations.
		</li>
		<li>
			<strong>Refunds for event registrations</strong> follow the refund policy the host sets for
			each event (full refund until the event starts, full refund until 24 hours before, or no
			refund), shown on the event page. You can cancel a registration from the event page; if
			your order is refund-eligible the refund is issued automatically, including our platform
			fee. If the <em>host</em> cancels an occurrence, every paid registration for it is refunded
			in full regardless of the policy.
		</li>
		<li>
			<strong>Donations</strong> to a fundraiser are payments to the fundraiser's owner, made
			into that person's own Stripe account. Threkir does not verify charitable status, is not a
			party to any commitment the fundraiser owner makes to pass funds on, and does not issue
			tax receipts. Check the fundraiser owner's identity and promises before donating; nothing
			on a fundraiser page is tax or financial advice.
		</li>
		<li>
			<strong>If you host paid events or fundraisers</strong>, you must onboard a payout account
			with Stripe and accept the Stripe Connected Account Agreement. You are the merchant of
			record: you own refunds, chargebacks (including our platform fee being reversed on a
			refund or chargeback), and your own tax reporting. You must describe events accurately,
			honour the refund policy you set, and use donation proceeds consistently with what your
			fundraiser page says.
		</li>
	</ul>

	<h2>7. Acceptable use</h2>
	<p>You agree not to:</p>
	<ul>
		<li>Reverse-engineer the service or extract data via automated means without our written permission.</li>
		<li>Upload content that infringes someone else's rights, including GPS tracks that belong to others.</li>
		<li>Harass other users, post unlawful content, or attempt to impersonate anyone.</li>
		<li>Use the service to commit fraud, send spam, or distribute malware.</li>
		<li>Attempt to access another user's account or private data.</li>
		<li>List an event or fundraiser that is deceptive, unlawful, or that you do not intend to deliver.</li>
	</ul>

	<h2>8. Safety</h2>
	<p>
		Running and exercise carry inherent risks. Training advice and AI Coach responses are
		informational only and do not constitute medical advice — consult a qualified healthcare
		professional before starting a new training program. Real-time spectator tracking and the
		safety-contact features depend on your phone's network and battery state, may be delayed or
		absent without warning, and are <strong>not an emergency service</strong>. In an emergency,
		contact your local emergency services directly.
	</p>

	<h2>9. Disclaimers</h2>
	<p>
		Threkir is provided "as is". To the maximum extent permitted by law, we disclaim implied
		warranties of merchantability, fitness for a particular purpose, and non-infringement.
		Nothing in these terms limits or excludes our liability for matters that, under your local
		law, cannot be limited or excluded — including death or personal injury caused by our
		negligence, and statutory consumer rights in the EU, UK, Australia, and elsewhere (for EU and
		UK consumers, this includes your legal remedies if a digital service is not supplied or does
		not conform to the contract).
	</p>

	<h2>10. Liability cap</h2>
	<p>
		To the extent permitted by law, our total liability to you for any claim arising from your
		use of the service is limited to the greater of (a) the amount you paid us in the 12 months
		preceding the event giving rise to the claim and (b) US$50. This cap does not apply where
		applicable law prohibits a cap on our liability, and does not limit the non-excludable
		rights described in section 9.
	</p>

	<h2>11. Indemnification</h2>
	<p>
		If a third party brings a claim against us arising from your content, your violation of
		these terms, or your conduct as an event host or fundraiser owner (including tax, refund, or
		chargeback obligations that are yours under section 6), you agree to indemnify us for the
		resulting damages and reasonable costs. This section does not apply where prohibited by your
		local consumer law, and does not require you to indemnify us for our own negligence.
	</p>

	<h2>12. Termination</h2>
	<p>
		You may close your account at any time from Settings → Delete account. We may suspend or
		terminate accounts that violate these terms, with notice except where notice would not be
		practical (for example, security incidents). You may appeal by emailing
		<a href="mailto:hello@threkir.com">hello@threkir.com</a>.
	</p>
	<p>
		When your account is closed, we delete your personal data on the schedule in the
		<a href="/privacy">Privacy Policy</a>.
	</p>

	<h2>13. Changes</h2>
	<p>
		We may update these terms from time to time. Material changes will be announced in-app and
		by email at least 30 days before they take effect. Continued use after that constitutes
		acceptance; if you do not agree, close your account before the changes take effect.
	</p>

	<h2>14. Governing law + disputes</h2>
	<p>
		If you have a problem, email <a href="mailto:hello@threkir.com">hello@threkir.com</a> first —
		most issues are resolved informally within a few days.
	</p>
	<p>
		These terms are governed by the laws of
		{#if OPERATOR.governingLaw}{OPERATOR.governingLaw}{:else}<em>the governing-law state, pending
			publication here</em>{/if}, and disputes will be resolved in the courts located there,
		except that either party may bring an eligible claim in small-claims court. If you are a
		consumer, nothing in this section deprives you of the protection of mandatory
		consumer-protection law of your country of residence, or of your right to sue there.
	</p>

	<h2>15. General</h2>
	<ul>
		<li><strong>Severability.</strong> If a provision of these terms is unenforceable, the rest remains in effect.</li>
		<li><strong>Entire agreement.</strong> These terms, the <a href="/privacy">Privacy Policy</a>, and the <a href="/cookie-notice">Cookie Notice</a> are the whole agreement between us about the service.</li>
		<li><strong>No waiver.</strong> Not enforcing a provision is not a waiver of it.</li>
		<li><strong>Assignment.</strong> You may not assign these terms; we may assign them as part of a sale or reorganisation of the service, with notice to you.</li>
		<li><strong>Notices.</strong> We send notices to your account email address; legal notices to us go to the contact addresses below.</li>
		<li><strong>Force majeure.</strong> Neither party is liable for delay or failure caused by events beyond its reasonable control.</li>
		<li><strong>Export.</strong> You may not use the service in violation of applicable export-control or sanctions law.</li>
	</ul>

	<h2>16. Contact</h2>
	<p>
		General: <a href="mailto:hello@threkir.com">hello@threkir.com</a>
		<br />Billing: <a href="mailto:billing@threkir.com">billing@threkir.com</a>
		<br />Privacy: <a href="mailto:privacy@threkir.com">privacy@threkir.com</a>
		<br />Security: <a href="mailto:security@threkir.com">security@threkir.com</a>
		<br />Copyright: <a href="mailto:dmca@threkir.com">dmca@threkir.com</a>
		<br />Postal: {#if OPERATOR.postalAddress}{OPERATOR.postalAddress}{:else}<em>pending
			publication — use the email addresses above in the meantime</em>{/if}
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
</style>
