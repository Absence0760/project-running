<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';
</script>

<footer class="landing-footer">
	<span>&copy; Threkir — {m('landing.footerTagline')}</span>
	<div class="footer-links">
		{#if auth.loggedIn}
			<a href="/dashboard">{m('landing.openApp')}</a>
		{:else}
			<a href="/login">{m('landing.signIn')}</a>
		{/if}
		<a href="/#apps">{m('landing.navApps')}</a>
		<a href="/#features">{m('landing.navFeatures')}</a>
		<a href="/learn">{m('landing.navLearn')}</a>
		<a href="/privacy">{m('landing.footerPrivacy')}</a>
		<a href="/terms">{m('landing.footerTerms')}</a>
		<a href="/cookie-notice">{m('landing.footerCookies')}</a>
		<a href="/health-data-notice">{m('landing.footerHealthData')}</a>
	</div>
</footer>

<style>
	.landing-footer {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-lg) var(--space-2xl);
		color: var(--color-text-tertiary);
		font-size: 0.85rem;
		background: var(--color-bg);
		border-top: 1px solid var(--color-border);
		/* In a flex-column page shell (the /learn pages), pin to the
		   bottom of short pages; inert in normal flow (the landing). */
		margin-top: auto;
	}

	.footer-links {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-lg);
	}

	.footer-links a {
		color: var(--color-text-secondary);
		transition: color var(--transition-fast);
	}

	.footer-links a:hover {
		color: var(--color-text);
	}

	@media (max-width: 768px) {
		.landing-footer {
			flex-direction: column;
			gap: var(--space-sm);
		}
	}
</style>
