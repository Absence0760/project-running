<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { m } from '$lib/i18n/store.svelte';

	// overlay = transparent white-on-dark chrome laid over the landing
	// hero; solid = the same nav on a themed surface for the other
	// public pages (/learn). One component so the marketing surface
	// can't drift between the two again.
	let { overlay = false }: { overlay?: boolean } = $props();
</script>

<nav class="landing-nav" class:overlay class:solid={!overlay}>
	<a href="/" class="landing-logo" aria-label="Threkir">
		{#if overlay}
			<img src="/wordmark-light.svg" alt="Threkir" class="landing-wordmark" />
		{:else}
			<img src="/wordmark.svg" alt="Threkir" class="landing-wordmark on-light" />
			<img src="/wordmark-light.svg" alt="Threkir" class="landing-wordmark on-dark" />
		{/if}
	</a>
	<div class="nav-links">
		<a href="/#apps" class="nav-link">{m('landing.navApps')}</a>
		<a href="/#features" class="nav-link">{m('landing.navFeatures')}</a>
		<a href="/learn" class="nav-link">{m('landing.navLearn')}</a>
		{#if auth.loggedIn}
			<a href="/dashboard" class="nav-signin">{m('landing.openApp')}</a>
		{:else}
			<a href="/login" class="nav-signin">{m('landing.signIn')}</a>
		{/if}
	</div>
</nav>

<style>
	/* Both variants share their box metrics, so the wordmark, the nav
	   links, and the Sign In pill land in exactly the same place on the
	   landing page and on /learn. The variants used to set their own
	   padding and disagreed — solid was 15px shorter, so every item in
	   the header jumped up 8px when a visitor clicked Learn. Only what
	   MUST differ between an overlay and an in-flow bar (position,
	   ground, border) belongs in the variant blocks below. */
	.landing-nav {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-lg) var(--space-2xl);
	}

	.landing-nav.overlay {
		position: absolute;
		top: 0;
		inset-inline-start: 0;
		inset-inline-end: 0;
		z-index: 10;
	}

	.landing-nav.solid {
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
	}

	.landing-logo {
		display: flex;
		align-items: center;
		text-decoration: none;
	}

	.landing-wordmark {
		height: 2rem;
		width: auto;
		display: block;
	}

	/* The solid header sits on a themed surface, so swap between the
	   dark-text and white-text wordmarks with the theme (explicit
	   html[data-theme] wins; auto/unset follows the OS preference). */
	.solid .landing-wordmark.on-dark {
		display: none;
	}
	:global([data-theme='dark']) .solid .landing-wordmark.on-light {
		display: none;
	}
	:global([data-theme='dark']) .solid .landing-wordmark.on-dark {
		display: block;
	}
	@media (prefers-color-scheme: dark) {
		:global([data-theme='auto']) .solid .landing-wordmark.on-light,
		:global(html:not([data-theme])) .solid .landing-wordmark.on-light {
			display: none;
		}
		:global([data-theme='auto']) .solid .landing-wordmark.on-dark,
		:global(html:not([data-theme])) .solid .landing-wordmark.on-dark {
			display: block;
		}
	}

	.nav-links {
		display: flex;
		align-items: center;
		gap: var(--space-lg);
	}

	.nav-link {
		font-size: 0.9rem;
		font-weight: 500;
		transition: color var(--transition-fast);
	}

	.overlay .nav-link {
		color: rgba(255, 255, 255, 0.72);
	}

	.overlay .nav-link:hover {
		color: #ffffff;
	}

	.solid .nav-link {
		color: var(--color-text-secondary);
	}

	.solid .nav-link:hover {
		color: var(--color-text);
	}

	.nav-signin {
		font-weight: 500;
		padding: var(--space-sm) var(--space-lg);
		border-radius: var(--radius-md);
		transition: all var(--transition-fast);
	}

	.overlay .nav-signin {
		color: rgba(255, 255, 255, 0.8);
		border: 1px solid rgba(255, 255, 255, 0.25);
		backdrop-filter: blur(8px);
	}

	.overlay .nav-signin:hover {
		border-color: rgba(255, 255, 255, 0.6);
		color: #ffffff;
		background: rgba(255, 255, 255, 0.1);
	}

	.solid .nav-signin {
		color: var(--color-text-secondary);
		border: 1px solid var(--color-border);
	}

	.solid .nav-signin:hover {
		border-color: var(--color-primary);
		color: var(--color-primary);
	}

	@media (max-width: 768px) {
		.nav-link {
			display: none;
		}
	}
</style>
