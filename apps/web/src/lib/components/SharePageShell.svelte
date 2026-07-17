<script lang="ts">
	import type { Snippet } from 'svelte';
	import { m } from '$lib/i18n/store.svelte';

	interface Props {
		children: Snippet;
	}

	let { children }: Props = $props();
</script>

<div class="share-page">
	<header class="share-header">
		<a href="/" class="share-logo">Threkir</a>
	</header>

	{@render children()}

	<footer class="share-footer">
		<a href="/">{m('shareRun.footerHome')}</a>
		<span class="dot">&middot;</span>
		<a href="/login">{m('shareRun.signIn')}</a>
	</footer>
</div>

<style>
	.share-page {
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}

	.share-header {
		padding: var(--space-sm) var(--space-md);
		border-bottom: 1px solid var(--color-border);
		background: var(--color-surface);
	}

	.share-logo {
		font-weight: 700;
		font-size: 1.15rem;
		color: var(--color-primary);
		text-decoration: none;
	}

	.share-footer {
		margin-top: auto;
		padding: var(--space-lg) var(--space-md);
		border-top: 1px solid var(--color-border);
		text-align: center;
		font-size: 0.85rem;
		color: var(--color-text-tertiary);
		background: var(--color-surface);
	}

	.share-footer a {
		color: var(--color-text-secondary);
		text-decoration: none;
	}

	.share-footer a:hover {
		color: var(--color-primary);
	}

	.dot {
		color: var(--color-text-tertiary);
		margin: 0 0.3rem;
	}

	@media (min-width: 48rem) {
		.share-header {
			padding: var(--space-md) var(--space-xl);
		}
	}
</style>
