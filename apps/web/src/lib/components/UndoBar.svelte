<script lang="ts">
	import { onMount } from 'svelte';
	import { beforeNavigate } from '$app/navigation';
	import { undoStore } from '$lib/stores/undo.svelte';
	import { showToast } from '$lib/stores/toast.svelte';
	import { m } from '$lib/i18n/store.svelte';

	const pending = $derived(undoStore.pending);

	// Leaving the surface the row was on ends the undo offer: the bar
	// would be describing a list the user can no longer see. Committing
	// (rather than cancelling) honours the intent they already expressed.
	beforeNavigate(() => {
		void undoStore.flush();
	});

	onMount(() => {
		// A tab close during the window can't be awaited, so the fetch may
		// never leave. That fails in the safe direction — the row survives
		// and reappears on the next load, rather than being destroyed with
		// no way back.
		const commit = () => void undoStore.flush();
		window.addEventListener('pagehide', commit);
		return () => window.removeEventListener('pagehide', commit);
	});

	function undo() {
		undoStore.undo();
		showToast(m('undo.restored'), 'success');
	}
</script>

<!--
	The role="status" + aria-live="polite" region is ALWAYS in the DOM,
	with only the bar inside it conditional: most screen readers do not
	announce a live region that enters the document already carrying its
	content, so a `{#if}` around the region itself would announce
	nothing. aria-atomic re-reads the whole offer — what was removed AND
	that undo exists — without stealing focus. The countdown is
	deliberately NOT in here: a ticking number would re-announce on every
	tick. WCAG 2.2.1 is met by the `undo_window_s` preference, which can
	turn the limit off entirely; hover/focus additionally pauses it.
-->
<div
	class="undo-region"
	role="status"
	aria-live="polite"
	aria-atomic="true"
	onmouseenter={undoStore.pause}
	onmouseleave={undoStore.resume}
	onfocusin={undoStore.pause}
	onfocusout={undoStore.resume}
>
	{#if pending}
		<div class="undo-bar" data-testid="undo-bar">
			<p class="undo-message">
				{pending.message}<span class="visually-hidden"> {m('undo.hint')}</span>
			</p>
			<div class="undo-actions">
				<button type="button" class="undo-action" data-testid="undo-action" onclick={undo}>
					{m('undo.action')}
				</button>
				<button
					type="button"
					class="undo-dismiss"
					data-testid="undo-dismiss"
					aria-label={m('undo.dismiss')}
					onclick={() => void undoStore.flush()}
				>
					<span class="material-symbols" aria-hidden="true">close</span>
				</button>
			</div>
			{#if pending.windowMs > 0}
				{#key pending.id}
					<div
						class="undo-progress"
						class:paused={pending.paused}
						style:animation-duration={`${pending.windowMs}ms`}
						aria-hidden="true"
					></div>
				{/key}
			{/if}
		</div>
	{/if}
</div>

<style>
	.undo-region {
		position: fixed;
		bottom: var(--space-lg);
		inset-inline-start: var(--space-lg);
		z-index: var(--z-toast);
	}
	.undo-bar {
		position: relative;
		display: flex;
		align-items: center;
		gap: var(--space-lg);
		max-width: min(28rem, calc(100vw - 2 * var(--space-lg)));
		padding: var(--space-2xs) var(--space-2xs) var(--space-2xs) var(--space-lg);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		background: var(--color-surface);
		color: var(--color-text);
		box-shadow: var(--shadow-lg);
		overflow: hidden;
	}
	.undo-message {
		margin: 0;
		font-size: 0.85rem;
		font-weight: 500;
	}
	.undo-actions {
		display: flex;
		align-items: center;
		gap: var(--space-xs);
		margin-inline-start: auto;
	}
	.undo-action {
		/* 44 px floor — the same tap-target minimum comment-tap-targets.spec
		   polices on the row buttons that open this bar. */
		display: flex;
		align-items: center;
		justify-content: center;
		min-inline-size: 44px;
		min-block-size: 44px;
		padding: var(--space-xs) var(--space-sm);
		border: none;
		border-radius: var(--radius-sm);
		background: transparent;
		color: var(--color-primary);
		font: inherit;
		font-size: 0.85rem;
		font-weight: 600;
		cursor: pointer;
	}
	.undo-action:hover {
		background: var(--color-bg-secondary);
	}
	.undo-dismiss {
		display: flex;
		align-items: center;
		justify-content: center;
		min-inline-size: 44px;
		min-block-size: 44px;
		border: none;
		border-radius: var(--radius-sm);
		background: transparent;
		color: var(--color-text-secondary);
		cursor: pointer;
	}
	.undo-dismiss:hover {
		background: var(--color-bg-secondary);
	}
	.undo-dismiss .material-symbols {
		font-size: 1.1rem;
	}
	.undo-progress {
		position: absolute;
		bottom: 0;
		inset-inline-start: 0;
		height: 2px;
		background: var(--color-primary);
		transform-origin: left center;
		animation-name: undo-countdown;
		animation-timing-function: linear;
		animation-fill-mode: forwards;
		inline-size: 100%;
	}
	.undo-progress.paused {
		animation-play-state: paused;
	}
	@keyframes undo-countdown {
		from { transform: scaleX(1); }
		to { transform: scaleX(0); }
	}
	/* The bar still expires on the same schedule under reduced motion —
	   only the shrinking indicator is stilled, so the visual cue becomes
	   a static rule rather than a moving one. */
	@media (prefers-reduced-motion: reduce) {
		.undo-progress {
			animation: none;
			opacity: 0.4;
		}
	}
</style>
