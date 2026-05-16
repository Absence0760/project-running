<script lang="ts">
	import { onMount } from 'svelte';
	import { consent } from '$lib/consent.svelte';

	// `mounted` gates the banner so it's NEVER in the prerendered HTML.
	// Without this, the static build ships with `consent.pending = true`
	// (no localStorage available at prerender time), the browser parses
	// the HTML and shows the banner instantly, then the hydration tick
	// re-reads localStorage and hides it — a visible flash for every
	// returning user. Cost of this gate: a single tick of delay before
	// the banner appears for genuine first-time visitors.
	let mounted = $state(false);
	let dismissed = $state(false);
	onMount(() => {
		mounted = true;
	});

	function accept() {
		consent.set('accepted');
		dismissed = true;
		window.location.reload();
	}

	function reject() {
		consent.set('rejected');
		dismissed = true;
	}
</script>

{#if mounted && consent.pending && !dismissed}
	<div class="banner" role="dialog" aria-modal="false" aria-labelledby="cookie-title" aria-describedby="cookie-desc">
		<div class="copy">
			<strong id="cookie-title">Cookies + error monitoring</strong>
			<p id="cookie-desc">
				We use a small number of cookies to keep you signed in (strictly necessary). With your
				consent we also load <a href="https://sentry.io/legal/dpa/" target="_blank" rel="noopener noreferrer">Sentry</a>
				to monitor errors so we can fix bugs faster. Map tiles, the AI Coach, and Storage
				signed URLs only run when you use the relevant feature.
				<a href="/cookie-notice">Learn more</a>.
			</p>
		</div>
		<div class="actions">
			<button type="button" class="btn btn-outline" onclick={reject}>Reject</button>
			<button type="button" class="btn btn-primary" onclick={accept}>Accept</button>
		</div>
	</div>
{/if}

<style>
	.banner {
		position: fixed;
		inset-block-end: var(--space-md);
		inset-inline-start: var(--space-md);
		inset-inline-end: var(--space-md);
		max-width: 42rem;
		margin-inline: auto;
		background: var(--color-surface);
		color: var(--color-text);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-lg);
		padding: var(--space-md) var(--space-lg);
		box-shadow: var(--shadow-lg);
		display: flex;
		flex-direction: column;
		gap: var(--space-sm);
		z-index: var(--z-cookie);
	}
	.copy strong {
		display: block;
		font-size: 1rem;
		margin-bottom: var(--space-2xs);
	}
	.copy p {
		margin: 0;
		font-size: 0.9rem;
		line-height: 1.5;
		color: var(--color-text-secondary);
	}
	.actions {
		display: flex;
		gap: var(--space-sm);
		justify-content: flex-end;
	}
	@media (min-width: 640px) {
		.banner {
			flex-direction: row;
			align-items: center;
		}
		.copy {
			flex: 1;
		}
	}
</style>
