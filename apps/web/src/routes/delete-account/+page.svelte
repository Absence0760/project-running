<script lang="ts">
	const lastUpdated = '2026-07-14';
</script>

<svelte:head>
	<title>Delete your account — Threkir</title>
	<meta
		name="description"
		content="How to delete your Threkir account and all associated data, with or without the app installed."
	/>
</svelte:head>

<div class="legal-page">
	<h1>Delete your account</h1>
	<p class="lead">
		This page explains how to permanently delete your Threkir account and the data associated
		with it. You do not need the app installed to request deletion.
	</p>
	<p class="meta">Last updated: {lastUpdated}</p>

	<h2>1. Delete your account yourself</h2>
	<p>Deletion is self-service and takes effect immediately:</p>
	<ul>
		<li>
			<strong>On the web</strong>: sign in, open
			<a href="/settings/account">Settings → Account</a>, and choose
			<strong>Delete account</strong>. You will be asked to type your account email to confirm.
			(Opening that link while signed out takes you through sign-in and back.)
		</li>
		<li>
			<strong>In the mobile app</strong>: Settings → Account → Delete account, with the same
			typed confirmation.
		</li>
	</ul>
	<p>
		Deletion is <strong>permanent and cannot be undone</strong>. When it completes we send a
		one-time confirmation email to the account address as a receipt.
	</p>

	<h2>2. If you can't sign in</h2>
	<p>
		Email <a href="mailto:privacy@threkir.com">privacy@threkir.com</a> from the email address on
		the account and ask us to delete it. We verify the request by matching (or confirming a link
		sent to) that address, then run the same deletion described below and confirm when it is
		done — within one month at the latest, usually much sooner.
	</p>

	<h2>3. What is deleted</h2>
	<p>
		Deleting the account removes your data across our database and file storage, including:
	</p>
	<ul>
		<li>your profile (name, avatar, settings, follower relationships);</li>
		<li>runs and their GPS tracks, routes, race results, and personal records;</li>
		<li>photos and every other file you uploaded, including generated data exports;</li>
		<li>gym workouts, routines, session plans, food logs, and body metrics;</li>
		<li>training plans, coach chat history, and AI Coach consent records;</li>
		<li>posts, comments, kudos, direct messages, and club memberships;</li>
		<li>notifications and push-notification tokens;</li>
		<li>
			linked third-party resources: a connected Strava authorisation is revoked, a RevenueCat
			subscriber record is deleted, and a connected Stripe payout account is unlinked and
			closed (Stripe retains transaction records under its own legal obligations).
		</li>
	</ul>

	<h2>4. What is retained, and for how long</h2>
	<ul>
		<li>
			<strong>Encrypted backups</strong>: a deleted account may persist in point-in-time-recovery
			backups for up to <strong>28 days</strong> before they roll off. Backups are never used to
			restore a deleted account.
		</li>
		<li>
			<strong>A minimal deletion audit record</strong>: a one-way hashed identifier and outcome
			counts, kept so we can prove the deletion happened. It cannot be used to identify you or
			recover any data.
		</li>
		<li>
			<strong>Payment transaction records</strong>: retained by the payment processors (Stripe,
			the app stores) under their own legal obligations; we hold no card details ourselves.
		</li>
	</ul>
	<p>
		The full retention schedule for every data category is in the
		<a href="/privacy">Privacy Policy</a>.
	</p>

	<h2>5. Deleting some data without closing the account</h2>
	<p>To delete individual data without deleting the account:</p>
	<ul>
		<li>
			<strong>Runs, routes, photos, gym workouts, food-log entries, posts, comments</strong>:
			open the item and use its Delete control. Runs can also be bulk-deleted from the Runs
			list via multi-select.
		</li>
		<li>
			<strong>Connected services</strong> (Strava, parkrun, and similar): disconnect them in
			Settings → Integrations; disconnecting revokes our access.
		</li>
		<li>
			<strong>Anything else, or if you prefer not to do it in the app</strong>: email
			<a href="mailto:privacy@threkir.com">privacy@threkir.com</a> describing the data to
			delete, and we will action it with the same verification and timeline as section 2.
		</li>
	</ul>
	<p>
		Deleted items leave encrypted backups within the same 28-day window described above. You can
		also <a href="/settings/account">export your data</a> before deleting anything.
	</p>

	<h2>6. Related documents</h2>
	<p>
		<a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms of Service</a> ·
		<a href="/health-data-notice">Consumer Health Data Privacy Policy</a> ·
		<a href="/cookie-notice">Cookie Notice</a>
	</p>
</div>

<style>
	.legal-page {
		max-width: 48rem;
		margin: 0 auto;
		padding: var(--space-xl) var(--space-2xl);
		line-height: 1.6;
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
