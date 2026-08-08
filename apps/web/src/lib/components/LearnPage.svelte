<script lang="ts">
	import type { Snippet } from 'svelte';
	import PublicHeader from './PublicHeader.svelte';
	import PublicFooter from './PublicFooter.svelte';

	// `prose` narrows the column to a reading measure for a guide body;
	// `wide` is the card-grid width the hub and category pages share.
	let { width = 'wide', children }: { width?: 'wide' | 'prose'; children: Snippet } = $props();
</script>

<div class="learn-page" class:prose={width === 'prose'}>
	<PublicHeader />
	{@render children()}
	<PublicFooter />
</div>

<style>
	.learn-page {
		--learn-col: 64rem;
		min-height: 100vh;
		background: var(--color-bg);
		display: flex;
		flex-direction: column;
	}

	.learn-page.prose {
		--learn-col: 44rem;
	}

	/* One definition of the column every band on a learn page sits in.
	   Each page had its own copy, and they drifted — the hub's header
	   ended up 8rem narrower than the card grid directly beneath it, so
	   the heading and the cards did not share a left edge. Pages still
	   own their vertical padding; only the horizontal frame lives here. */
	.learn-page :global(.learn-column) {
		max-width: var(--learn-col);
		margin-inline: auto;
		width: 100%;
	}
</style>
